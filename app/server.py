"""HTTP server for Node Warden.

The process listens on loopback and is exposed by an nginx gateway under
/warden/.  It keeps no command strings from HTTP: routes only accept ids from
the validated registry, and every subprocess is a fixed argv list.
"""
from __future__ import annotations

import hmac
import json
import logging
import os
import re
import shutil
import threading
import time
import traceback
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit
from urllib.request import Request as UrlRequest, build_opener, ProxyHandler

from . import __version__, systems
from .backups import BackupError, BackupManager
from .config import ConfigError, Settings, load_backups, load_services
from .history import HistoryStore
from .security import (
    LoginLimiter, SessionManager, b64url_encode, client_ip, generate_key,
    hash_key, key_id_for, origin_allowed, parse_cookies, validate_new_key,
    verify_key,
)

LOG = logging.getLogger("node_warden")

STATIC_TYPES = {
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".ico": "image/x-icon",
}
STATIC_FILES = {"style.css", "app.js", "favicon.svg"}
BACKUP_ID_RE = re.compile(r"^backup-[0-9]{8}T[0-9]{6}Z(?:-[0-9]+)?$")


class ApiError(Exception):
    def __init__(self, status: int, message: str, code: str = "error"):
        super().__init__(message)
        self.status = status
        self.message = message
        self.code = code


class PanelApp:
    def __init__(self, settings: Settings, services: list[dict], backup_entries: list[dict]):
        self.settings = settings
        self.services = services
        self.service_map = {service["id"]: service for service in services}
        self.sessions = SessionManager(settings.session_secret, settings.session_ttl,
                                       key_id_for(settings.key_sha256))
        self.key_sha256 = settings.key_sha256
        self.key_changed_at = None
        self.login_limiter = LoginLimiter(settings.login_max_fails, settings.login_window)
        self.key_limiter = LoginLimiter(10, 300)
        self.started_at = time.time()
        self._lock = threading.Lock()
        self._cache: dict[str, tuple[float, object]] = {}
        self._cache_lock = threading.Lock()
        self._record_lock = threading.Lock()
        self._last_record = 0.0
        self._action_lock = threading.Lock()
        self._last_actions: dict[tuple[str, str], float] = {}
        self._audit_lock = threading.Lock()
        self._monitor_stop = threading.Event()
        self._last_states: dict[str, bool] = {}

        settings.data_dir.mkdir(parents=True, exist_ok=True)
        try:
            os.chmod(settings.data_dir, 0o700)
        except OSError:
            pass
        if settings.audit_file.parent:
            settings.audit_file.parent.mkdir(parents=True, exist_ok=True)
        self.history = HistoryStore(settings.history_db, settings.history_retention_days)
        self.backups = BackupManager(backup_entries, settings.backup_dir,
                                     tar_bin=settings.tar_bin, timeout=settings.backup_timeout,
                                     max_backups=settings.max_backups)

    # ------------------------------------------------------------------
    # cache and audit

    def _cached(self, key: str, ttl: float, factory):
        now = time.time()
        with self._cache_lock:
            entry = self._cache.get(key)
            if entry and entry[0] > now:
                return entry[1]
        value = factory()
        with self._cache_lock:
            self._cache[key] = (now + ttl, value)
        return value

    def invalidate(self, prefix: str | None = None) -> None:
        with self._cache_lock:
            if prefix is None:
                self._cache.clear()
            else:
                for key in list(self._cache):
                    if key.startswith(prefix):
                        self._cache.pop(key, None)

    def audit(self, action: str, detail: str, ip: str, result: str = "ok") -> None:
        record = {
            "ts": datetime.now(timezone.utc).isoformat(),
            "action": action,
            "detail": str(detail)[:500],
            "ip": ip,
            "result": result,
        }
        line = json.dumps(record, ensure_ascii=False) + "\n"
        with self._audit_lock:
            try:
                self.settings.audit_file.parent.mkdir(parents=True, exist_ok=True)
                if self.settings.audit_file.exists() and self.settings.audit_file.stat().st_size > 5 * 1024 * 1024:
                    rotated = self.settings.audit_file.with_name(self.settings.audit_file.name + ".1")
                    os.replace(self.settings.audit_file, rotated)
                with self.settings.audit_file.open("a", encoding="utf-8") as handle:
                    handle.write(line)
                    try:
                        os.chmod(self.settings.audit_file, 0o600)
                    except OSError:
                        pass
            except OSError:
                LOG.warning("cannot write audit log", exc_info=True)

    def read_audit(self, limit: int = 100, query: str = "") -> list[dict]:
        limit = max(1, min(int(limit), 300))
        try:
            lines = self.settings.audit_file.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return []
        items = []
        query = query.strip().lower()
        for line in reversed(lines[-4000:]):
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(item, dict):
                continue
            if query and query not in json.dumps(item, ensure_ascii=False).lower():
                continue
            items.append(item)
            if len(items) >= limit:
                break
        return items

    # ------------------------------------------------------------------
    # service snapshots

    def _record_rows(self, rows: list[dict]) -> None:
        now = time.time()
        with self._record_lock:
            if now - self._last_record < 30:
                return
            self._last_record = now
        for row in rows:
            try:
                self.history.record(
                    row["id"], bool(row["status"].get("active")), bool(row["health"].get("ok")),
                    row["health"].get("latency_ms"), row["health"].get("detail", "")[:500],
                )
            except Exception:
                LOG.warning("cannot record history for %s", row["id"], exc_info=True)

    def service_rows(self, record: bool = False) -> list[dict]:
        rows = []
        for service in self.services:
            status = systems.service_status(service, self.settings)
            health = systems.health_check(service.get("health", {}), self.settings)
            rows.append({
                "id": service["id"],
                "name": service["name"],
                "kind": service["kind"],
                "target": service["target"],
                "description": service.get("description", ""),
                "actions": service.get("actions", []),
                "nginx": bool(service.get("nginx")),
                "health_config": service.get("health", {}),
                "logs": service.get("logs", []),
                "status": status,
                "health": health,
                "uptime": self.history.availability(service["id"], 24),
            })
        if record:
            self._record_rows(rows)
        return rows

    def _docker_stats(self) -> dict:
        return systems.docker_stats(self.services, self.settings)

    def _certificate(self) -> dict:
        return systems.certificate_info(self.settings.cert_domain,
                                        self.settings.cert_connect_host,
                                        self.settings.cert_connect_port)

    def overview(self) -> dict:
        def build():
            rows = self.service_rows(record=True)
            metrics = self._cached("docker_stats", 15, self._docker_stats)
            for row in rows:
                row["metrics"] = metrics.get(row["target"])
            host = self._cached("host", 5, lambda: systems.host_info(self.settings))
            cert = self._cached("cert", 300, self._certificate)
            ports = self._cached("ports", 10, systems.listening_ports)
            backups = self.backups.list()
            return {
                "as_of": datetime.now(timezone.utc).isoformat(),
                "host": host,
                "certificate": cert,
                "services": rows,
                "ports": ports,
                "audit": self.read_audit(6),
                "backups": {"count": len(backups), "latest": backups[0] if backups else None},
                "panel": self.panel_info(),
            }
        return self._cached("overview", 5, build)

    def metrics(self, hours: int = 24, points: int = 96) -> dict:
        hours = max(1, min(int(hours), 24 * 7))
        points = max(12, min(int(points), 288))
        host = self._cached("host", 5, lambda: systems.host_info(self.settings))
        series = []
        for service in self.services:
            try:
                series.append({
                    "id": service["id"],
                    "name": service["name"],
                    "series": self.history.service_series(service["id"], hours, points),
                })
            except Exception:
                LOG.warning("cannot build service series for %s", service["id"], exc_info=True)
        return {
            "as_of": datetime.now(timezone.utc).isoformat(),
            "hours": hours,
            "points": points,
            "host": host,
            "host_series": self.history.host_series(hours, points),
            "services": series,
        }

    def proxies(self) -> dict:
        return self._cached("proxies", 20, lambda: systems.proxy_overview(self.settings))

    def cn_setup_info(self) -> dict:
        public_url = self.settings.public_url.rstrip("/")
        parsed = urlsplit(public_url)
        origin = f"{parsed.scheme}://{parsed.netloc}" if parsed.scheme and parsed.netloc else ""
        domain = parsed.hostname or self.settings.node_host
        docker_ready = any("crproxy" in item["id"].lower() for item in self.services)
        git_ready = any("ghproxy" in item["id"].lower() for item in self.services)
        opts = []
        if origin and docker_ready:
            opts.extend(["--docker-mirror", origin])
        if origin and git_ready:
            opts.extend(["--git-mirror", origin])
        script_url = public_url + "/bootstrap.sh"
        toolbox_url = public_url + "/toolbox.sh"
        command = "sudo bash <(curl -fsSL %s) cn-setup" % script_url
        if opts:
            command += " " + " ".join(opts)
        command += " --yes --non-interactive"
        return {
            "domain": domain,
            "origin": origin,
            "script_url": script_url,
            "toolbox_url": toolbox_url,
            "docker_mirror": origin if docker_ready else "",
            "git_mirror": origin if git_ready else "",
            "docker_ready": docker_ready,
            "git_ready": git_ready,
            "command": command,
        }

    def panel_info(self) -> dict:
        return {
            "name": "Node Warden",
            "version": __version__,
            "public_url": self.settings.public_url + "/",
            "base_path": self.settings.base_path,
            "hostname": self.settings.node_host,
            "started_at": datetime.fromtimestamp(self.started_at, timezone.utc).isoformat(),
            "monitor_enabled": self.settings.monitor_enabled,
            "monitor_interval": self.settings.monitor_interval,
            "key_fingerprint": self.sessions.key_id[:8],
            "key_changed_at": self.key_changed_at,
            "session_ttl": self.settings.session_ttl,
            "backup_count": len(self.backups.list()),
            "cn_setup": self.cn_setup_info(),
        }

    # ------------------------------------------------------------------
    # auth and key rotation

    def login(self, key: str, ip: str) -> dict:
        if not self.login_limiter.allow(ip):
            raise ApiError(429, "登录尝试过于频繁，请稍后再试", "login_rate_limited")
        if not verify_key(key, self.key_sha256):
            self.login_limiter.failure(ip)
            self.audit("login", "访问密钥验证失败", ip, "failed")
            raise ApiError(401, "访问密钥不正确", "bad_key")
        self.login_limiter.success(ip)
        session = self.sessions.issue()
        self.audit("login", "登录成功", ip)
        return session

    def _atomic_write(self, path: Path, text: str, mode: int = 0o600) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name("." + path.name + ".tmp")
        with tmp.open("w", encoding="utf-8") as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)

    def change_key(self, current_key: str, new_key: str, ip: str) -> dict:
        if not self.key_limiter.allow(ip):
            raise ApiError(429, "密钥验证过于频繁，请稍后再试", "key_rate_limited")
        if not verify_key(current_key, self.key_sha256):
            self.key_limiter.failure(ip)
            self.audit("key-change", "当前访问密钥验证失败", ip, "failed")
            raise ApiError(401, "当前访问密钥不正确", "bad_current_key")
        problem = validate_new_key(new_key)
        if problem:
            raise ApiError(400, problem, "weak_key")
        if verify_key(new_key, self.key_sha256):
            raise ApiError(400, "新密钥不能与当前密钥相同", "same_key")
        new_sha = hash_key(new_key)
        new_kid = key_id_for(new_sha)
        try:
            self._persist_key(new_sha, new_key)
        except OSError as exc:
            LOG.error("cannot persist new key: %s", exc, exc_info=True)
            raise ApiError(500, "无法写入密钥文件，请在服务器上检查 /etc/node-warden 与 /var/lib/node-warden 权限", "key_write_failed")
        self.key_sha256 = new_sha
        self.sessions.set_key_id(new_kid)
        self.key_changed_at = datetime.now(timezone.utc).isoformat()
        self.key_limiter.success(ip)
        session = self.sessions.issue()
        self.audit("key-change", "网页修改访问密钥成功；旧会话已失效", ip)
        self.invalidate()
        return session

    def _persist_key(self, new_sha: str, new_key: str) -> None:
        env_path = self.settings.env_file
        if not env_path.exists():
            raise OSError(f"env file does not exist: {env_path}")
        original = env_path.read_text(encoding="utf-8")
        lines = original.splitlines()
        replaced = False
        for index, line in enumerate(lines):
            if line.startswith("PANEL_KEY_SHA256="):
                lines[index] = "PANEL_KEY_SHA256=" + new_sha
                replaced = True
                break
        if not replaced:
            lines.append("PANEL_KEY_SHA256=" + new_sha)
        new_env = "\n".join(lines) + "\n"
        self._atomic_write(env_path, new_env, 0o600)
        try:
            self._atomic_write(self.settings.key_file, new_key + "\n", 0o600)
        except OSError:
            LOG.error("new key is active but recovery key file could not be written", exc_info=True)

    def verify_current_key(self, key: str, ip: str) -> None:
        if not self.key_limiter.allow(ip):
            raise ApiError(429, "密钥验证过于频繁，请稍后再试", "key_rate_limited")
        if not verify_key(key, self.key_sha256):
            self.key_limiter.failure(ip)
            self.audit("reauth", "敏感操作密钥验证失败", ip, "failed")
            raise ApiError(401, "访问密钥不正确", "bad_key")
        self.key_limiter.success(ip)

    # ------------------------------------------------------------------
    # monitor

    def start_monitor(self) -> None:
        if not self.settings.monitor_enabled:
            return
        thread = threading.Thread(target=self._monitor_loop, name="node-warden-monitor", daemon=True)
        thread.start()

    def stop_monitor(self) -> None:
        self._monitor_stop.set()

    def _monitor_loop(self) -> None:
        self._monitor_stop.wait(2)
        while not self._monitor_stop.is_set():
            try:
                rows = self.service_rows(record=False)
                self._record_rows(rows)
                host = systems.host_info(self.settings)
                live = host.get("metrics") or {}
                self.history.record_host({
                    "cpu": host.get("cpu_percent"),
                    "memory_percent": (host.get("memory") or {}).get("percent"),
                    "load1": (host.get("load") or [0])[0],
                    "rx_bps": (live.get("network") or {}).get("rx_bps", 0),
                    "tx_bps": (live.get("network") or {}).get("tx_bps", 0),
                    "disk_read_bps": (live.get("disk_io") or {}).get("read_bps", 0),
                    "disk_write_bps": (live.get("disk_io") or {}).get("write_bps", 0),
                    "tcp_connections": live.get("tcp_connections", 0),
                })
                self._alert_transitions(rows)
                self.history.prune()
            except Exception:
                LOG.warning("monitor iteration failed", exc_info=True)
            self._monitor_stop.wait(self.settings.monitor_interval)

    def _alert_transitions(self, rows: list[dict]) -> None:
        for row in rows:
            up = bool(row["status"].get("active")) and bool(row["health"].get("ok"))
            previous = self._last_states.get(row["id"])
            self._last_states[row["id"]] = up
            if previous is None or previous == up:
                continue
            state = "up" if up else "down"
            self.audit("alert", f"{row['name']} 转为 {state}", "monitor", state)
            if self.settings.alert_webhook:
                payload = {
                    "source": "node-warden",
                    "state": state,
                    "service": row["name"],
                    "service_id": row["id"],
                    "detail": row["health"].get("detail", ""),
                    "at": datetime.now(timezone.utc).isoformat(),
                }
                try:
                    request = UrlRequest(self.settings.alert_webhook,
                                         data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                                         headers={"Content-Type": "application/json", "User-Agent": "node-warden/alert"},
                                         method="POST")
                    with build_opener(ProxyHandler({})).open(request, timeout=6) as response:
                        response.read(1)
                except Exception:
                    LOG.warning("alert webhook failed", exc_info=True)

    # ------------------------------------------------------------------
    # actions

    def action(self, service_id: str, action: str, ip: str) -> dict:
        service = self.service_map.get(service_id)
        if service is None:
            raise ApiError(404, "服务不存在", "unknown_service")
        if action not in service.get("actions", []):
            raise ApiError(400, "该服务不支持此动作", "unsupported_action")
        key = (service_id, action)
        now = time.monotonic()
        with self._action_lock:
            previous = self._last_actions.get(key, 0)
            if self.settings.action_cooldown and now - previous < self.settings.action_cooldown:
                raise ApiError(429, "动作执行过于频繁，请稍后再试", "action_rate_limited")
            self._last_actions[key] = now
        result = systems.run_service_action(service, action, self.settings)
        self.audit("action", f"{service['name']}: {action} -> {'ok' if result.get('ok') else 'failed'}", ip,
                   "ok" if result.get("ok") else "failed")
        self.invalidate()
        return result

    def reveal_singbox(self, key: str, ip: str) -> dict:
        self.verify_current_key(key, ip)
        data = systems.singbox_reveal(self.settings)
        self.audit("singbox-reveal", "查看 sing-box 连接信息", ip)
        return data

    def cert_renew_dry_run(self, ip: str) -> dict:
        now = time.monotonic()
        with self._action_lock:
            previous = self._last_actions.get(("cert", "dry-run"), 0)
            if now - previous < 60:
                raise ApiError(429, "证书检查过于频繁，请稍后再试", "action_rate_limited")
            self._last_actions[("cert", "dry-run")] = now
        result = systems.certbot_dry_run(self.settings)
        self.audit("cert-dry-run", f"certbot dry-run -> {'ok' if result.get('ok') else 'failed'}", ip,
                   "ok" if result.get("ok") else "failed")
        self.invalidate("cert")
        return result


class Handler(BaseHTTPRequestHandler):
    server_version = "node-warden"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, app: PanelApp, **kwargs):
        self.app = app
        self._headers_sent = False
        super().__init__(*args, **kwargs)

    def log_message(self, fmt, *args):
        LOG.info("%s - %s", self.address_string(), fmt % args)

    # ------------------------------------------------------------------
    # low-level responses

    def _common_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; "
                         "connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        self.send_header("Cache-Control", "no-store, max-age=0")

    def _send_bytes(self, status: int, body: bytes, content_type: str,
                    extra: dict | None = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self._common_headers()
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self._headers_sent = True
        if self.command != "HEAD":
            try:
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def _json(self, status: int, data: dict, extra: dict | None = None) -> None:
        body = json.dumps(data, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self._send_bytes(status, body, "application/json; charset=utf-8", extra)

    def _error(self, status: int, message: str, code: str) -> None:
        self._json(status, {"error": message, "code": code})

    def _set_cookie(self, value: str, max_age: int) -> None:
        secure = self.app.settings.cookie_secure == "always" or (
            self.app.settings.cookie_secure == "auto" and self.app.settings.public_url.startswith("https://"))
        parts = [
            f"{self.app.settings.cookie_name}={value}",
            f"Path={self.app.settings.cookie_path}",
            "HttpOnly",
            "SameSite=Strict",
            f"Max-Age={max_age}",
        ]
        if secure:
            parts.append("Secure")
        return "; ".join(parts)

    def _set_session(self, session: dict) -> str:
        return self._set_cookie(session["cookie"], self.app.settings.session_ttl)

    def _clear_session(self) -> str:
        return self._set_cookie("", 0)

    # ------------------------------------------------------------------
    # request helpers

    def _client(self) -> str:
        return client_ip(self.headers, self.client_address[0], self.app.settings.trust_proxy)

    def _origin_ok(self) -> bool:
        return origin_allowed(self.headers.get("Origin"), self.app.settings.allowed_origin,
                              self.app.settings.public_url + "/")

    def _session(self) -> dict | None:
        cookies = parse_cookies(self.headers.get("Cookie"))
        return self.app.sessions.verify(cookies.get(self.app.settings.cookie_name))

    def _require_auth(self) -> dict:
        session = self._session()
        if session is None:
            raise ApiError(401, "登录已过期，请重新登录", "auth_required")
        return session

    def _require_csrf(self) -> dict:
        session = self._require_auth()
        if not self._origin_ok():
            raise ApiError(403, "请求来源不被允许", "bad_origin")
        supplied = (self.headers.get("X-CSRF-Token") or "").strip()
        expected = str(session.get("csrf", ""))
        if not supplied or not expected or not hmac.compare_digest(supplied, expected):
            raise ApiError(403, "CSRF 校验失败，请刷新页面重试", "bad_csrf")
        return session

    def _read_json(self) -> dict:
        if not self._origin_ok():
            raise ApiError(403, "请求来源不被允许", "bad_origin")
        content_type = (self.headers.get("Content-Type") or "").split(";", 1)[0].strip().lower()
        if content_type != "application/json":
            raise ApiError(415, "Content-Type 必须是 application/json", "bad_content_type")
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError as exc:
            raise ApiError(400, "Content-Length 无效", "bad_length") from exc
        if length < 0 or length > self.app.settings.max_body_bytes:
            raise ApiError(413, "请求体过大", "body_too_large")
        raw = self.rfile.read(length) if length else b""
        if not raw:
            return {}
        try:
            value = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ApiError(400, "请求体不是有效 JSON", "bad_json") from exc
        if not isinstance(value, dict):
            raise ApiError(400, "请求体必须是 JSON 对象", "bad_json")
        return value

    def _session_payload(self, session: dict) -> dict:
        return {
            "authenticated": True,
            "csrf": session["csrf"],
            "expires_at": session.get("expires_at", session.get("exp")),
            "issued_at": session.get("iat"),
            "key_fingerprint": self.app.sessions.key_id[:8],
            "version": __version__,
            "base_path": self.app.settings.base_path,
        }

    # ------------------------------------------------------------------
    # routing

    def do_HEAD(self):
        self._dispatch("HEAD")

    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def _dispatch(self, method: str) -> None:
        try:
            self._route(method)
        except ApiError as exc:
            if not self._headers_sent:
                self._error(exc.status, exc.message, exc.code)
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception:
            LOG.error("unhandled request error: %s %s", method, self.path, exc_info=True)
            if not self._headers_sent:
                self._error(500, "服务器内部错误", "internal_error")

    def _route(self, method: str) -> None:
        parsed = urlsplit(self.path)
        path = unquote(parsed.path)
        base = self.app.settings.base_path
        if path == base:
            self.send_response(301)
            self.send_header("Location", base + "/")
            self.send_header("Content-Length", "0")
            self._common_headers()
            self.end_headers()
            self._headers_sent = True
            return
        if not path.startswith(base + "/"):
            raise ApiError(404, "Not found", "not_found")
        rel = path[len(base):] or "/"
        if method in {"GET", "HEAD"} and rel == "/":
            self._serve_index()
            return
        if method in {"GET", "HEAD"} and rel == "/bootstrap.sh":
            self._serve_bootstrap()
            return
        if method in {"GET", "HEAD"} and rel == "/toolbox.sh":
            self._serve_toolbox()
            return
        if method in {"GET", "HEAD"} and rel.startswith("/static/"):
            self._serve_static(rel[len("/static/"):])
            return
        if rel.startswith("/api/"):
            self._serve_api(method, rel[len("/api/"):], parse_qs(parsed.query))
            return
        raise ApiError(404, "Not found", "not_found")

    def _serve_index(self) -> None:
        path = self.app.settings.static_dir / "index.html"
        try:
            body = path.read_bytes()
        except OSError:
            raise ApiError(500, "index.html 缺失", "missing_index")
        self._send_bytes(200, body, "text/html; charset=utf-8")

    def _serve_bootstrap(self) -> None:
        self._serve_script("bootstrap.sh")

    def _serve_toolbox(self) -> None:
        self._serve_script("toolbox.sh")

    def _serve_script(self, name: str) -> None:
        path = Path(__file__).resolve().parent.parent / name
        try:
            body = path.read_bytes()
        except OSError:
            raise ApiError(404, "Not found", "not_found")
        self._send_bytes(200, body, "text/x-shellscript; charset=utf-8")

    def _serve_static(self, name: str) -> None:
        if name not in STATIC_FILES:
            raise ApiError(404, "Not found", "not_found")
        path = self.app.settings.static_dir / name
        try:
            body = path.read_bytes()
        except OSError:
            raise ApiError(404, "Not found", "not_found")
        content_type = STATIC_TYPES.get(path.suffix.lower(), "application/octet-stream")
        self._send_bytes(200, body, content_type)

    def _serve_api(self, method: str, route: str, query: dict) -> None:
        segments = [part for part in route.strip("/").split("/") if part]
        if not segments:
            raise ApiError(404, "Not found", "not_found")
        head = segments[0]
        if head == "session" and len(segments) == 1:
            if method not in {"GET", "HEAD"}:
                raise ApiError(405, "Method not allowed", "method_not_allowed")
            session = self._session()
            if session is None:
                self._json(200, {"authenticated": False, "version": __version__,
                                 "base_path": self.app.settings.base_path})
            else:
                self._json(200, self._session_payload(session))
            return
        if head == "login" and len(segments) == 1:
            if method != "POST":
                raise ApiError(405, "Method not allowed", "method_not_allowed")
            self._origin_or_403()
            data = self._read_json()
            key = data.get("key")
            if not isinstance(key, str) or not key:
                raise ApiError(400, "请输入访问密钥", "missing_key")
            session = self.app.login(key, self._client())
            self._json(200, self._session_payload(session), {"Set-Cookie": self._set_session(session)})
            return
        if head == "logout" and len(segments) == 1:
            if method != "POST":
                raise ApiError(405, "Method not allowed", "method_not_allowed")
            self._require_csrf()
            self.app.audit("logout", "退出登录", self._client())
            self._json(200, {"ok": True}, {"Set-Cookie": self._clear_session()})
            return

        session = self._require_auth()
        if head == "overview" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            self._json(200, self.app.overview())
            return
        if head == "metrics" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            try:
                hours = int((query.get("hours") or ["24"])[0])
                points = int((query.get("points") or ["96"])[0])
            except ValueError as exc:
                raise ApiError(400, "hours 和 points 必须是整数", "bad_range") from exc
            self._json(200, self.app.metrics(hours, points))
            return
        if head == "proxies" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            self._json(200, self.app.proxies())
            return
        if head == "services" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            self._json(200, {"as_of": datetime.now(timezone.utc).isoformat(),
                             "services": self.app.service_rows(record=True)})
            return
        if head == "services" and len(segments) >= 3:
            service_id = segments[1]
            action_name = segments[2]
            if action_name == "logs" and len(segments) == 3:
                self._method(method, {"GET", "HEAD"})
                service = self.app.service_map.get(service_id)
                if not service:
                    raise ApiError(404, "服务不存在", "unknown_service")
                source = (query.get("source") or [""])[0]
                try:
                    tail = int((query.get("tail") or ["200"])[0])
                except ValueError:
                    tail = 200
                try:
                    data = systems.read_logs(service, source, tail, self.app.settings)
                except ValueError as exc:
                    raise ApiError(400, str(exc), "bad_log_source") from exc
                self._json(200, data)
                return
            if action_name == "action" and len(segments) == 3:
                self._method(method, {"POST"})
                self._require_csrf()
                data = self._read_json()
                action_value = data.get("action")
                if not isinstance(action_value, str):
                    raise ApiError(400, "动作无效", "bad_action")
                self._json(200, self.app.action(service_id, action_value, self._client()))
                return
        if head == "key" and len(segments) == 2 and segments[1] == "change":
            self._method(method, {"POST"})
            self._require_csrf()
            data = self._read_json()
            current_key = data.get("current_key")
            new_key = data.get("new_key")
            if not isinstance(current_key, str) or not isinstance(new_key, str):
                raise ApiError(400, "当前密钥和新密钥都必须是字符串", "bad_key")
            session = self.app.change_key(current_key, new_key, self._client())
            self._json(200, self._session_payload(session), {"Set-Cookie": self._set_session(session)})
            return
        if head == "singbox" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            data = self.app._cached("singbox", 30, lambda: systems.singbox_summary(self.app.settings))
            self._json(200, data)
            return
        if head == "singbox" and len(segments) == 2 and segments[1] == "reveal":
            self._method(method, {"POST"})
            self._require_csrf()
            data = self._read_json()
            key = data.get("key")
            if not isinstance(key, str) or not key:
                raise ApiError(400, "请输入当前访问密钥", "missing_key")
            self._json(200, self.app.reveal_singbox(key, self._client()))
            return
        if head == "singbox" and len(segments) == 2 and segments[1] == "config":
            self._method(method, {"GET", "HEAD"})
            file_id = (query.get("file") or [""])[0]
            try:
                data = systems.singbox_config_text(self.app.settings, file_id, reveal=False)
            except (ValueError, OSError) as exc:
                raise ApiError(400, str(exc), "bad_config") from exc
            self._json(200, data)
            return
        if head == "backups" and len(segments) == 1:
            if method in {"GET", "HEAD"}:
                self._json(200, {"backups": self.app.backups.list()})
                return
            if method == "POST":
                self._require_csrf()
                self._read_json()
                try:
                    manifest = self.app.backups.create()
                except BackupError as exc:
                    raise ApiError(400, str(exc), "backup_failed") from exc
                self.app.audit("backup-create", f"创建备份 {manifest['id']}", self._client())
                self.app.invalidate("overview")
                self._json(200, manifest)
                return
        if head == "backups" and len(segments) == 3 and segments[2] == "download":
            self._method(method, {"GET", "HEAD"})
            backup_id = segments[1]
            if not BACKUP_ID_RE.match(backup_id):
                raise ApiError(400, "备份 id 无效", "bad_backup_id")
            try:
                manifest = self.app.backups.get(backup_id)
            except BackupError as exc:
                raise ApiError(404, str(exc), "backup_not_found") from exc
            self.app.audit("backup-download", f"下载备份 {backup_id}", self._client())
            self._serve_backup(Path(manifest["archive"]), backup_id)
            return
        if head == "backups" and len(segments) == 3 and segments[2] == "delete":
            self._method(method, {"POST"})
            self._require_csrf()
            self._read_json()
            backup_id = segments[1]
            if not BACKUP_ID_RE.match(backup_id):
                raise ApiError(400, "备份 id 无效", "bad_backup_id")
            try:
                self.app.backups.delete(backup_id)
            except BackupError as exc:
                raise ApiError(404, str(exc), "backup_not_found") from exc
            self.app.audit("backup-delete", f"删除备份 {backup_id}", self._client())
            self.app.invalidate("overview")
            self._json(200, {"ok": True})
            return
        if head == "cert" and len(segments) == 2 and segments[1] == "renew":
            self._method(method, {"POST"})
            self._require_csrf()
            self._read_json()
            self._json(200, self.app.cert_renew_dry_run(self._client()))
            return
        if head == "audit" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            try:
                limit = int((query.get("limit") or ["100"])[0])
            except ValueError:
                limit = 100
            q = (query.get("q") or [""])[0]
            self._json(200, {"items": self.app.read_audit(limit, q)})
            return
        if head == "settings" and len(segments) == 1:
            self._method(method, {"GET", "HEAD"})
            self._json(200, self.app.panel_info())
            return
        raise ApiError(404, "Not found", "not_found")

    def _method(self, method: str, allowed: set[str]) -> None:
        if method not in allowed:
            raise ApiError(405, "Method not allowed", "method_not_allowed")

    def _origin_or_403(self) -> None:
        if not self._origin_ok():
            raise ApiError(403, "请求来源不被允许", "bad_origin")

    def _serve_backup(self, path: Path, backup_id: str) -> None:
        try:
            size = path.stat().st_size
            handle = path.open("rb")
        except OSError as exc:
            raise ApiError(404, "备份文件不存在", "backup_not_found") from exc
        self.send_response(200)
        self.send_header("Content-Type", "application/gzip")
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f'attachment; filename="{backup_id}.tar.gz"')
        self._common_headers()
        self.end_headers()
        self._headers_sent = True
        if self.command == "HEAD":
            handle.close()
            return
        try:
            with handle:
                shutil.copyfileobj(handle, self.wfile)
        except (BrokenPipeError, ConnectionResetError):
            pass


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        settings = Settings.from_env()
        services = load_services(settings.services_file)
        backup_entries = load_backups(settings.services_file, settings.backup_allowed_roots)
    except ConfigError as exc:
        LOG.error("configuration error: %s", exc)
        return 2
    if not (settings.static_dir / "index.html").exists():
        LOG.error("static/index.html is missing")
        return 2
    app = PanelApp(settings, services, backup_entries)
    app.start_monitor()
    handler = lambda *args, **kwargs: Handler(*args, app=app, **kwargs)  # noqa: E731
    try:
        server = ThreadingHTTPServer((settings.host, settings.port), handler)
    except OSError as exc:
        LOG.error("cannot listen on %s:%s: %s", settings.host, settings.port, exc)
        return 2
    server.daemon_threads = True
    LOG.info("Node Warden %s listening on http://%s:%s%s/", __version__, settings.host, settings.port,
             settings.base_path)
    LOG.info("public URL: %s/", settings.public_url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        app.stop_monitor()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
