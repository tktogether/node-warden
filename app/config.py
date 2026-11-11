"""Configuration and registry loading for Node Warden.

Everything the panel may control is declared in root-owned JSON files.  The
panel never accepts a command, unit name, container name or log path from an
HTTP request: it only accepts service ids, action ids, backup ids and log
source ids that were validated here.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from urllib.parse import urlparse


class ConfigError(RuntimeError):
    """Raised when panel configuration is missing or unsafe."""


SERVICE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")
CONTAINER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
UNIT_RE = re.compile(r"^[A-Za-z0-9_.@-]+\.(service|timer)$")
HOST_RE = re.compile(r"^[A-Za-z0-9_.:\[\]-]{1,253}$")
DOMAIN_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$")

ALLOWED_KINDS = {"docker", "systemd", "singbox"}
ALLOWED_ACTIONS = {
    "docker": {"restart", "start", "stop", "test", "reload"},
    "systemd": {"restart", "start", "stop", "reload"},
    "singbox": {"restart", "start", "stop", "check"},
}
ALLOWED_HEALTH = {"http", "tcp", "cert", "none"}
ALLOWED_LOG_TYPES = {"docker", "journal", "file"}


def _env(name: str, default: str | None = None) -> str | None:
    value = os.environ.get(name)
    if value is None or value == "":
        return default
    return value


def _env_int(name: str, default: int) -> int:
    raw = _env(name)
    if raw is None:
        return default
    try:
        return int(raw)
    except ValueError as exc:
        raise ConfigError(f"{name} must be an integer") from exc


def _env_bool(name: str, default: bool) -> bool:
    raw = _env(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


def _normalize_base_path(value: str) -> str:
    value = (value or "").strip()
    if not value.startswith("/"):
        raise ConfigError("PANEL_BASE_PATH must start with /")
    value = "/" + value.strip("/")
    if "//" in value or "?" in value or "#" in value:
        raise ConfigError("PANEL_BASE_PATH is not a clean URL path")
    return value


class Settings:
    """Runtime settings, built only from the process environment."""

    def __init__(self) -> None:
        self.base_dir = Path(__file__).resolve().parent.parent
        version_file = self.base_dir / "VERSION"
        try:
            self.version = version_file.read_text(encoding="utf-8").strip() or "dev"
        except OSError:
            self.version = "dev"

        self.host = _env("PANEL_HOST", "127.0.0.1") or "127.0.0.1"
        self.port = _env_int("PANEL_PORT", 9090)
        if not (1 <= self.port <= 65535):
            raise ConfigError("PANEL_PORT must be between 1 and 65535")

        self.base_path = _normalize_base_path(_env("PANEL_BASE_PATH", "/warden") or "/warden")
        default_public = f"http://127.0.0.1:{self.port}{self.base_path}/"
        self.public_url = (_env("PANEL_PUBLIC_URL", default_public) or "").rstrip("/")
        parsed = urlparse(self.public_url)
        if parsed.scheme not in {"http", "https"} or not parsed.hostname:
            raise ConfigError("PANEL_PUBLIC_URL must be an absolute http(s) URL")
        expected_path = self.base_path.rstrip("/")
        if expected_path and parsed.path.rstrip("/") != expected_path:
            raise ConfigError("PANEL_PUBLIC_URL path must match PANEL_BASE_PATH")
        if expected_path == "" and parsed.path not in {"", "/"}:
            raise ConfigError("PANEL_PUBLIC_URL path must match PANEL_BASE_PATH")
        self.allowed_origin = (_env("PANEL_ALLOWED_ORIGIN") or f"{parsed.scheme}://{parsed.netloc}").rstrip("/")
        parsed_origin = urlparse(self.allowed_origin)
        if parsed_origin.scheme not in {"http", "https"} or not parsed_origin.hostname:
            raise ConfigError("PANEL_ALLOWED_ORIGIN must be an absolute http(s) origin")
        self.cert_domain = _env("PANEL_CERT_DOMAIN") or parsed.hostname
        if not DOMAIN_RE.match(self.cert_domain):
            raise ConfigError("PANEL_CERT_DOMAIN is not a valid hostname")
        self.cert_connect_host = _env("PANEL_CERT_CONNECT_HOST", "127.0.0.1") or "127.0.0.1"
        self.cert_connect_port = _env_int("PANEL_CERT_CONNECT_PORT", 443)
        if not (1 <= self.cert_connect_port <= 65535):
            raise ConfigError("PANEL_CERT_CONNECT_PORT is invalid")
        self.node_host = _env("PANEL_NODE_HOST", self.cert_domain) or self.cert_domain
        if not HOST_RE.match(self.node_host):
            raise ConfigError("PANEL_NODE_HOST is not a valid host or IP")

        self.docker_mirror_url = (_env("PANEL_DOCKER_MIRROR_URL", f"https://{self.cert_domain}/v2/") or "").rstrip("/") + "/"
        self.gateway_url = (_env("PANEL_GATEWAY_URL", f"https://{self.cert_domain}/") or "").rstrip("/") + "/"
        self.gateway_status_url = _env("PANEL_GATEWAY_STATUS_URL", "http://127.0.0.1:8083/__status") or ""
        self.ghproxy_stats_url = _env("PANEL_GHPROXY_STATS_URL", "http://127.0.0.1:8082/__stats") or ""
        self.ghproxy_test_url = _env("PANEL_GHPROXY_TEST_URL",
                                     "https://raw.githubusercontent.com/git/git/master/README.md") or ""
        for name, value in (("PANEL_DOCKER_MIRROR_URL", self.docker_mirror_url),
                            ("PANEL_GATEWAY_URL", self.gateway_url),
                            ("PANEL_GATEWAY_STATUS_URL", self.gateway_status_url),
                            ("PANEL_GHPROXY_STATS_URL", self.ghproxy_stats_url),
                            ("PANEL_GHPROXY_TEST_URL", self.ghproxy_test_url)):
            if value and urlparse(value).scheme not in {"http", "https"}:
                raise ConfigError(f"{name} must be an absolute http(s) URL")
        self.gateway_config = Path(_env("PANEL_GATEWAY_CONFIG", "/root/gateway/nginx.conf") or "")
        self.gateway_access_log = Path(_env("PANEL_GATEWAY_ACCESS_LOG", "/root/gateway/logs/access.log") or "")

        self.key_sha256 = (_env("PANEL_KEY_SHA256") or "").strip().lower()
        if not re.fullmatch(r"[0-9a-f]{64}", self.key_sha256):
            raise ConfigError("PANEL_KEY_SHA256 must be a 64-character lowercase hex SHA-256 digest")
        self.session_secret = (_env("PANEL_SESSION_SECRET") or "").strip()
        if len(self.session_secret) < 32:
            raise ConfigError("PANEL_SESSION_SECRET must be at least 32 characters")
        self.session_ttl = _env_int("PANEL_SESSION_TTL", 43200)
        if not (300 <= self.session_ttl <= 7 * 24 * 3600):
            raise ConfigError("PANEL_SESSION_TTL must be between 300 and 604800 seconds")

        self.services_file = Path(_env("PANEL_SERVICES_FILE", "/etc/node-warden/services.json") or "")
        self.data_dir = Path(_env("PANEL_DATA_DIR", "/var/lib/node-warden") or "")
        self.env_file = Path(_env("PANEL_ENV_FILE", "/etc/node-warden/panel.env") or "")
        self.key_file = Path(_env("PANEL_KEY_FILE", str(self.data_dir / "access-key")) or "")
        self.audit_file = Path(_env("PANEL_AUDIT_FILE", str(self.data_dir / "audit.log")) or "")
        self.history_db = Path(_env("PANEL_HISTORY_DB", str(self.data_dir / "history.db")) or "")
        self.backup_dir = Path(_env("PANEL_BACKUP_DIR", str(self.data_dir / "backups")) or "")
        self.static_dir = self.base_dir / "static"
        self.cookie_name = _env("PANEL_COOKIE_NAME", "nw_session") or "nw_session"
        self.cookie_secure = (_env("PANEL_COOKIE_SECURE", "auto") or "auto").lower()
        if self.cookie_secure not in {"auto", "always", "never"}:
            raise ConfigError("PANEL_COOKIE_SECURE must be auto, always or never")
        self.trust_proxy = _env_bool("PANEL_TRUST_PROXY", True)
        self.login_max_fails = _env_int("PANEL_LOGIN_MAX_FAILS", 8)
        self.login_window = _env_int("PANEL_LOGIN_WINDOW", 300)
        self.action_cooldown = _env_int("PANEL_ACTION_COOLDOWN", 2)
        if not (1 <= self.login_max_fails <= 100):
            raise ConfigError("PANEL_LOGIN_MAX_FAILS must be between 1 and 100")
        if not (10 <= self.login_window <= 86400):
            raise ConfigError("PANEL_LOGIN_WINDOW must be between 10 and 86400 seconds")
        if not (0 <= self.action_cooldown <= 60):
            raise ConfigError("PANEL_ACTION_COOLDOWN must be between 0 and 60 seconds")

        self.max_backups = _env_int("PANEL_MAX_BACKUPS", 20)
        if not (1 <= self.max_backups <= 100):
            raise ConfigError("PANEL_MAX_BACKUPS must be between 1 and 100")
        self.backup_timeout = _env_int("PANEL_BACKUP_TIMEOUT", 120)
        if not (10 <= self.backup_timeout <= 600):
            raise ConfigError("PANEL_BACKUP_TIMEOUT must be between 10 and 600 seconds")
        raw_roots = (_env("PANEL_BACKUP_ALLOWED_ROOTS", "/etc,/root,/var/www,/opt") or "").split(",")
        roots = []
        for raw_root in raw_roots:
            raw_root = raw_root.strip()
            if not raw_root:
                continue
            root = Path(raw_root)
            if not root.is_absolute() or str(root) == "/":
                raise ConfigError("PANEL_BACKUP_ALLOWED_ROOTS entries must be absolute non-root paths")
            roots.append(str(root.resolve()))
        if not roots:
            raise ConfigError("PANEL_BACKUP_ALLOWED_ROOTS must contain at least one path")
        self.backup_allowed_roots = tuple(roots)

        self.monitor_enabled = _env_bool("PANEL_MONITOR_ENABLED", True)
        self.monitor_interval = _env_int("PANEL_MONITOR_INTERVAL", 60)
        if not (10 <= self.monitor_interval <= 3600):
            raise ConfigError("PANEL_MONITOR_INTERVAL must be between 10 and 3600 seconds")
        self.history_retention_days = _env_int("PANEL_HISTORY_RETENTION_DAYS", 7)
        if not (1 <= self.history_retention_days <= 90):
            raise ConfigError("PANEL_HISTORY_RETENTION_DAYS must be between 1 and 90 days")
        self.alert_webhook = (_env("PANEL_ALERT_WEBHOOK") or "").strip()
        if self.alert_webhook:
            hook = urlparse(self.alert_webhook)
            if hook.scheme not in {"http", "https"} or not hook.hostname:
                raise ConfigError("PANEL_ALERT_WEBHOOK must be an absolute http(s) URL")

        self.docker_bin = _env("PANEL_DOCKER_BIN", "docker") or "docker"
        self.systemctl_bin = _env("PANEL_SYSTEMCTL_BIN", "systemctl") or "systemctl"
        self.journalctl_bin = _env("PANEL_JOURNALCTL_BIN", "journalctl") or "journalctl"
        self.tar_bin = _env("PANEL_TAR_BIN", "tar") or "tar"
        self.certbot_bin = _env("PANEL_CERTBOT_BIN", "certbot") or "certbot"
        self.singbox_bin = _env("PANEL_SINGBOX_BIN", "/etc/sing-box/bin/sing-box") or ""
        self.singbox_config = Path(_env("PANEL_SINGBOX_CONFIG", "/etc/sing-box/config.json") or "")
        self.singbox_conf_dir = Path(_env("PANEL_SINGBOX_CONF_DIR", "/etc/sing-box/conf") or "")
        self.singbox_service = _env("PANEL_SINGBOX_SERVICE", "sing-box.service") or "sing-box.service"
        if not UNIT_RE.match(self.singbox_service):
            raise ConfigError("PANEL_SINGBOX_SERVICE must be a .service unit name")

        self.max_log_tail = _env_int("PANEL_MAX_LOG_TAIL", 500)
        if not (10 <= self.max_log_tail <= 2000):
            raise ConfigError("PANEL_MAX_LOG_TAIL must be between 10 and 2000")
        self.max_body_bytes = _env_int("PANEL_MAX_BODY_BYTES", 32768)
        if not (1024 <= self.max_body_bytes <= 1048576):
            raise ConfigError("PANEL_MAX_BODY_BYTES must be between 1024 and 1048576")

        self.cookie_path = self.base_path if self.base_path != "/" else "/"

    @classmethod
    def from_env(cls) -> "Settings":
        return cls()


def _require_text(value, field: str, max_len: int = 300) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ConfigError(f"{field} must be a non-empty string")
    value = value.strip()
    if len(value) > max_len:
        raise ConfigError(f"{field} is too long")
    return value


def _validate_health(health, service_id: str) -> dict:
    if health is None:
        return {"type": "none"}
    if not isinstance(health, dict):
        raise ConfigError(f"services[{service_id}].health must be an object")
    kind = str(health.get("type", "none")).lower()
    if kind not in ALLOWED_HEALTH:
        raise ConfigError(f"services[{service_id}].health.type is not allowed")
    result = {"type": kind}
    if kind == "none":
        return result
    if kind == "http":
        url = _require_text(health.get("url"), f"services[{service_id}].health.url", 2048)
        if urlparse(url).scheme not in {"http", "https"}:
            raise ConfigError(f"services[{service_id}].health.url must be http(s)")
        expect = health.get("expect", [200])
        if not isinstance(expect, list) or not expect or len(expect) > 10:
            raise ConfigError(f"services[{service_id}].health.expect must be a non-empty list")
        codes = []
        for code in expect:
            if not isinstance(code, int) or not 100 <= code <= 599:
                raise ConfigError(f"services[{service_id}].health.expect contains an invalid status code")
            codes.append(code)
        result.update(url=url, expect=codes, insecure=bool(health.get("insecure", False)))
        return result
    if kind == "tcp":
        targets = health.get("targets")
        if targets is None and "host" in health and "port" in health:
            targets = [{"host": health.get("host"), "port": health.get("port")}]
        if not isinstance(targets, list) or not (1 <= len(targets) <= 8):
            raise ConfigError(f"services[{service_id}].health.targets must contain 1-8 targets")
        clean = []
        for target in targets:
            if not isinstance(target, dict):
                raise ConfigError(f"services[{service_id}].health.targets must be objects")
            host = _require_text(target.get("host"), "health target host", 253)
            port = target.get("port")
            if not isinstance(port, int) or not 1 <= port <= 65535:
                raise ConfigError(f"services[{service_id}].health port is invalid")
            clean.append({"host": host, "port": port})
        result["targets"] = clean
        return result
    if kind == "cert":
        domain = _require_text(health.get("domain"), f"services[{service_id}].health.domain", 253)
        if not DOMAIN_RE.match(domain):
            raise ConfigError(f"services[{service_id}].health.domain is invalid")
        result.update(domain=domain, connect_host=health.get("connect_host", "127.0.0.1"),
                      connect_port=health.get("connect_port", 443))
        return result
    return result


def _validate_logs(logs, service: dict) -> list[dict]:
    if logs is None:
        return []
    if not isinstance(logs, list) or len(logs) > 10:
        raise ConfigError(f"services[{service['id']}].logs must be a list")
    result = []
    seen = set()
    for source in logs:
        if not isinstance(source, dict):
            raise ConfigError(f"services[{service['id']}].logs entries must be objects")
        source_id = _require_text(source.get("id", "main"), f"services[{service['id']}].logs.id", 40)
        if not SERVICE_ID_RE.match(source_id) or source_id in seen:
            raise ConfigError(f"services[{service['id']}].logs.id is invalid or duplicated")
        seen.add(source_id)
        kind = str(source.get("type", "journal")).lower()
        if kind not in ALLOWED_LOG_TYPES:
            raise ConfigError(f"services[{service['id']}].logs.type is not allowed")
        label = _require_text(source.get("label", source_id), f"services[{service['id']}].logs.label", 80)
        item = {"id": source_id, "type": kind, "label": label}
        if kind == "docker":
            target = source.get("target", service.get("target"))
            if not isinstance(target, str) or not CONTAINER_RE.match(target):
                raise ConfigError(f"services[{service['id']}].logs docker target is invalid")
            item["target"] = target
        elif kind == "journal":
            unit = source.get("unit", service.get("target"))
            if not isinstance(unit, str) or not UNIT_RE.match(unit):
                raise ConfigError(f"services[{service['id']}].logs journal unit is invalid")
            item["unit"] = unit
        else:
            path = _require_text(source.get("path"), f"services[{service['id']}].logs.path", 1024)
            resolved = Path(path).resolve()
            if not str(resolved).startswith("/var/log/"):
                raise ConfigError(f"services[{service['id']}].logs.path must be below /var/log")
            item["path"] = str(resolved)
        result.append(item)
    return result


def load_services(path: Path | str) -> list[dict]:
    """Load and validate the root-owned service registry."""
    path = Path(path)
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ConfigError(f"cannot read services file {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"services file {path} is not valid JSON: {exc}") from exc
    if isinstance(raw, dict):
        raw = raw.get("services")
    if not isinstance(raw, list) or not raw:
        raise ConfigError("services file must contain a non-empty services list")
    if len(raw) > 64:
        raise ConfigError("services file contains too many services")

    services = []
    seen = set()
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            raise ConfigError(f"services[{index}] must be an object")
        service_id = _require_text(item.get("id"), f"services[{index}].id", 41)
        if not SERVICE_ID_RE.match(service_id) or service_id in seen:
            raise ConfigError(f"services[{index}].id is invalid or duplicated")
        seen.add(service_id)
        name = _require_text(item.get("name"), f"services[{service_id}].name", 80)
        kind = str(item.get("kind", "")).lower()
        if kind not in ALLOWED_KINDS:
            raise ConfigError(f"services[{service_id}].kind must be one of {sorted(ALLOWED_KINDS)}")
        target = _require_text(item.get("target"), f"services[{service_id}].target", 128)
        if kind == "docker" and not CONTAINER_RE.match(target):
            raise ConfigError(f"services[{service_id}].target is not a valid container name")
        if kind in {"systemd", "singbox"} and not UNIT_RE.match(target):
            raise ConfigError(f"services[{service_id}].target is not a valid systemd unit")

        raw_actions = item.get("actions", [])
        if not isinstance(raw_actions, list) or len(raw_actions) > 8:
            raise ConfigError(f"services[{service_id}].actions must be a list")
        actions = []
        for action in raw_actions:
            if not isinstance(action, str) or action not in ALLOWED_ACTIONS[kind]:
                raise ConfigError(f"services[{service_id}].action {action!r} is not allowed for {kind}")
            if action in {"test", "reload"} and not bool(item.get("nginx")):
                raise ConfigError(f"services[{service_id}].action {action} requires nginx=true")
            if action not in actions:
                actions.append(action)

        service = {
            "id": service_id,
            "name": name,
            "kind": kind,
            "target": target,
            "description": str(item.get("description", ""))[:300],
            "actions": actions,
            "nginx": bool(item.get("nginx", False)),
            "order": int(item.get("order", index)) if isinstance(item.get("order", index), int) else index,
            "health": _validate_health(item.get("health"), service_id),
            "logs": [],
        }
        service["logs"] = _validate_logs(item.get("logs"), service)
        services.append(service)
    services.sort(key=lambda s: (s["order"], s["id"]))
    return services


def load_services_by_id(path: Path | str) -> dict[str, dict]:
    return {service["id"]: service for service in load_services(path)}


def load_backups(path: Path | str, allowed_roots: tuple[str, ...]) -> list[dict]:
    """Load optional backup entries from the top-level 'backups' key.

    A backup entry is deliberately just a label and an absolute path.  The
    panel creates a tar archive of the configured path; HTTP callers cannot
    choose either the path or the archive name.
    """
    path = Path(path)
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ConfigError(f"cannot read services file {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise ConfigError(f"services file {path} is not valid JSON: {exc}") from exc
    entries = raw.get("backups", []) if isinstance(raw, dict) else []
    if entries is None:
        entries = []
    if not isinstance(entries, list) or len(entries) > 64:
        raise ConfigError("backups must be a list with at most 64 entries")

    roots = [Path(root).resolve() for root in allowed_roots]
    clean = []
    seen = set()
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise ConfigError(f"backups[{index}] must be an object")
        entry_id = _require_text(entry.get("id"), f"backups[{index}].id", 41)
        if not SERVICE_ID_RE.match(entry_id) or entry_id in seen:
            raise ConfigError(f"backups[{index}].id is invalid or duplicated")
        seen.add(entry_id)
        label = _require_text(entry.get("label", entry_id), f"backups[{entry_id}].label", 80)
        raw_path = _require_text(entry.get("path"), f"backups[{entry_id}].path", 1024)
        candidate = Path(raw_path)
        if not candidate.is_absolute() or str(candidate) == "/":
            raise ConfigError(f"backups[{entry_id}].path must be an absolute non-root path")
        resolved = candidate.resolve()
        if not any(resolved == root or resolved.is_relative_to(root) for root in roots):
            raise ConfigError(f"backups[{entry_id}].path is outside PANEL_BACKUP_ALLOWED_ROOTS")
        clean.append({
            "id": entry_id,
            "label": label,
            "path": str(resolved),
            "exists": resolved.exists(),
            "type": "dir" if resolved.is_dir() else "file",
        })
    return clean
