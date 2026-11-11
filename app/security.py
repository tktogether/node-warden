"""Authentication and request-safety primitives.

The panel uses a single high-entropy access key, verified against a SHA-256
digest, and a stateless, HMAC-signed session cookie.  A root-only recovery copy
of the key may exist outside this module.  Mutating requests also require a
per-session CSRF token.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import ipaddress
import json
import re
import secrets
import threading
import time
from collections import defaultdict, deque
from urllib.parse import urlparse


KEY_ID_RE = re.compile(r"^[0-9a-f]{16}$")


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def b64url_decode(text: str) -> bytes:
    padding = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + padding)


def hash_key(key: str) -> str:
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def verify_key(key: str, expected_sha256: str) -> bool:
    if not key or not expected_sha256:
        return False
    return hmac.compare_digest(hash_key(key), expected_sha256.lower())


def key_id_for(expected_sha256: str) -> str:
    return hashlib.sha256(expected_sha256.encode("utf-8")).hexdigest()[:16]


def generate_key() -> str:
    """Return a 256-bit URL-safe access key (43 characters)."""
    return secrets.token_urlsafe(32)


def validate_new_key(key: str) -> str | None:
    if not isinstance(key, str):
        return "访问密钥必须是字符串"
    if key != key.strip():
        return "访问密钥首尾不能有空白字符"
    if len(key) < 10:
        return "访问密钥至少需要 10 个字符"
    if len(key) > 256:
        return "访问密钥不能超过 256 个字符"
    if any(ch.isspace() for ch in key):
        return "访问密钥不能包含空白字符"
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in key):
        return "访问密钥不能包含控制字符"
    return None


class SessionManager:
    """Issue and verify stateless signed session cookies."""

    def __init__(self, secret: str, ttl: int, key_id: str):
        if len(secret) < 32:
            raise ValueError("session secret is too short")
        if not KEY_ID_RE.match(key_id):
            raise ValueError("key id is invalid")
        self._secret = secret.encode("utf-8")
        self.ttl = int(ttl)
        self._key_id = key_id
        self._lock = threading.Lock()

    @property
    def key_id(self) -> str:
        with self._lock:
            return self._key_id

    def set_key_id(self, key_id: str) -> None:
        """Rotate the key id in place; all existing cookies become invalid."""
        if not KEY_ID_RE.match(key_id):
            raise ValueError("key id is invalid")
        with self._lock:
            self._key_id = key_id

    def issue(self, now: int | None = None) -> dict:
        now = int(time.time() if now is None else now)
        csrf = secrets.token_urlsafe(24)
        with self._lock:
            key_id = self._key_id
        payload = {
            "v": 1,
            "iat": now,
            "exp": now + self.ttl,
            "csrf": csrf,
            "kid": key_id,
        }
        encoded = b64url_encode(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
        signature = hmac.new(self._secret, encoded.encode("ascii"), hashlib.sha256).digest()
        return {
            "cookie": f"{encoded}.{b64url_encode(signature)}",
            "csrf": csrf,
            "expires_at": payload["exp"],
            "iat": now,
        }

    def verify(self, cookie: str | None, now: int | None = None) -> dict | None:
        if not cookie or "." not in cookie:
            return None
        try:
            encoded, supplied_sig = cookie.split(".", 1)
            expected_sig = hmac.new(self._secret, encoded.encode("ascii"), hashlib.sha256).digest()
            if not hmac.compare_digest(b64url_decode(supplied_sig), expected_sig):
                return None
            payload = json.loads(b64url_decode(encoded).decode("utf-8"))
        except (ValueError, TypeError, KeyError, json.JSONDecodeError, UnicodeDecodeError):
            return None
        if not isinstance(payload, dict) or payload.get("v") != 1:
            return None
        if payload.get("kid") != self.key_id:
            return None
        now = int(time.time() if now is None else now)
        try:
            if int(payload.get("exp", 0)) <= now:
                return None
        except (TypeError, ValueError):
            return None
        csrf = payload.get("csrf")
        if not isinstance(csrf, str) or len(csrf) < 20:
            return None
        return payload


def parse_cookies(header: str | None) -> dict[str, str]:
    cookies: dict[str, str] = {}
    if not header:
        return cookies
    for part in header.split(";"):
        if "=" not in part:
            continue
        name, value = part.split("=", 1)
        name = name.strip()
        if name and name not in cookies:
            cookies[name] = value.strip()
    return cookies


class LoginLimiter:
    """Sliding-window login failure limiter, keyed by client IP."""

    def __init__(self, max_fails: int = 8, window: int = 300, max_ips: int = 2048):
        self.max_fails = max(1, int(max_fails))
        self.window = max(1, int(window))
        self.max_ips = max(16, int(max_ips))
        self._failures: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def _prune_locked(self, ip: str, now: float) -> None:
        queue = self._failures.get(ip)
        if queue is None:
            return
        cutoff = now - self.window
        while queue and queue[0] <= cutoff:
            queue.popleft()
        if not queue:
            self._failures.pop(ip, None)

    def allow(self, ip: str, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        with self._lock:
            self._prune_locked(ip, now)
            if len(self._failures) > self.max_ips:
                for key in list(self._failures)[: len(self._failures) - self.max_ips]:
                    self._failures.pop(key, None)
            return len(self._failures.get(ip, ())) < self.max_fails

    def failure(self, ip: str, now: float | None = None) -> None:
        now = time.monotonic() if now is None else now
        with self._lock:
            self._prune_locked(ip, now)
            self._failures[ip].append(now)

    def success(self, ip: str) -> None:
        with self._lock:
            self._failures.pop(ip, None)


def is_loopback(host: str) -> bool:
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return host in {"localhost", "localhost.localdomain"}


def client_ip(headers, remote_addr: str, trust_proxy: bool = True) -> str:
    """Return the real client IP behind the local nginx gateway."""
    remote = (remote_addr or "").strip()
    if trust_proxy and is_loopback(remote):
        forwarded = (headers.get("X-Real-IP") or "").strip()
        if forwarded:
            try:
                return str(ipaddress.ip_address(forwarded))
            except ValueError:
                pass
    try:
        return str(ipaddress.ip_address(remote))
    except ValueError:
        return remote or "unknown"


def origin_allowed(origin: str | None, allowed_origin: str, public_url: str) -> bool:
    """Reject browser requests that carry a foreign Origin header."""
    if not origin:
        return True
    candidate = origin.rstrip("/")
    if candidate == allowed_origin.rstrip("/"):
        return True
    parsed = urlparse(public_url)
    public_origin = f"{parsed.scheme}://{parsed.netloc}"
    return candidate == public_origin.rstrip("/")


def normalize_origin(origin: str) -> str:
    return origin.strip().rstrip("/")
