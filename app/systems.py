"""Read-only probes and fixed-argv actions for Node Warden.

No function in this module accepts a shell string.  Every command is a list,
and every target comes from the validated JSON registry or from Settings.
"""
from __future__ import annotations

import base64
import json
import os
import platform
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote, urlencode, urlsplit
from urllib.request import HTTPSHandler, ProxyHandler, Request, build_opener

SENSITIVE_KEYS = {
    "uuid", "password", "private_key", "public_key", "short_id", "pre_shared_key",
    "obfs_password", "auth_str", "token", "secret", "psk", "key",
}
MASK = "••••••••"

_CPU_LOCK = None
_CPU_LAST: tuple[int, int] | None = None


def _init_lock():
    global _CPU_LOCK
    if _CPU_LOCK is None:
        import threading
        _CPU_LOCK = threading.Lock()
    return _CPU_LOCK


def run(argv: list[str], timeout: int = 20, env: dict | None = None) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False, env=env)
    except FileNotFoundError as exc:
        return subprocess.CompletedProcess(argv, 127, "", f"command not found: {argv[0]} ({exc})")
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(argv, 124, "", f"command timed out after {timeout}s")
    except OSError as exc:
        return subprocess.CompletedProcess(argv, 126, "", f"cannot run {argv[0]}: {exc}")


def _text(result: subprocess.CompletedProcess, limit: int = 8000) -> str:
    value = (result.stdout or "") + (result.stderr or "")
    value = value.strip()
    return value[:limit]


def _parse_systemd_show(text: str) -> dict:
    values = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def service_status(service: dict, settings) -> dict:
    kind = service.get("kind")
    target = service.get("target", "")
    if kind == "docker":
        result = run([settings.docker_bin, "inspect", "--format",
                      "{{.State.Status}}|{{.State.StartedAt}}|{{.RestartCount}}|{{.Config.Image}}|{{.State.ExitCode}}",
                      target], timeout=10)
        if result.returncode != 0:
            return {"active": False, "state": "missing", "detail": _text(result, 400) or "container not found",
                    "target": target, "kind": kind}
        parts = (result.stdout or "").strip().split("|", 4)
        state = parts[0] if parts else "unknown"
        return {
            "active": state == "running",
            "state": state,
            "detail": state,
            "target": target,
            "kind": kind,
            "started_at": parts[1] if len(parts) > 1 else "",
            "restarts": int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0,
            "image": parts[3] if len(parts) > 3 else "",
            "exit_code": parts[4] if len(parts) > 4 else "",
        }
    result = run([settings.systemctl_bin, "show", "-p", "ActiveState", "-p", "SubState",
                  "-p", "MainPID", "-p", "ActiveEnterTimestamp", "-p", "NRestarts",
                  "--no-pager", target], timeout=10)
    if result.returncode != 0:
        return {"active": False, "state": "missing", "detail": _text(result, 400) or "unit not found",
                "target": target, "kind": kind}
    values = _parse_systemd_show(result.stdout or "")
    active_state = values.get("ActiveState", "unknown")
    substate = values.get("SubState", "")
    return {
        "active": active_state == "active",
        "state": active_state,
        "detail": f"{active_state} ({substate})" if substate else active_state,
        "target": target,
        "kind": kind,
        "main_pid": values.get("MainPID", ""),
        "active_enter": values.get("ActiveEnterTimestamp", ""),
        "restarts": int(values.get("NRestarts", "0") or 0) if values.get("NRestarts", "0").isdigit() else 0,
    }


def _tcp_check(target: dict) -> tuple[bool, str]:
    host = str(target.get("host", "")).strip("[]")
    port = int(target.get("port", 0))
    try:
        with socket.create_connection((host, port), timeout=2.5):
            return True, f"{host}:{port} 可连接"
    except OSError as exc:
        return False, f"{host}:{port} 不可连接: {exc}"


def _http_check(health: dict) -> tuple[bool, str]:
    url = health["url"]
    expected = set(health.get("expect") or [200])
    context = ssl._create_unverified_context() if health.get("insecure") else ssl.create_default_context()
    handlers = [ProxyHandler({})]
    if url.lower().startswith("https://"):
        handlers.append(HTTPSHandler(context=context))
    opener = build_opener(*handlers)
    request = Request(url, headers={"User-Agent": "node-warden/health"})
    code = None
    try:
        with opener.open(request, timeout=5) as response:
            code = response.status
            response.read(1)
        return code in expected, f"HTTP {code}"
    except Exception as exc:  # HTTPError and network errors both mean "not healthy"
        code = getattr(exc, "code", None)
        if code is not None:
            return code in expected, f"HTTP {code}"
        return False, f"请求失败: {exc}"


def _decode_certificate(der: bytes) -> dict:
    """Decode a DER certificate with the standard library.

    SSLSocket.getpeercert() returns an empty mapping when the connection uses
    CERT_NONE, so certificate checks decode the DER bytes through the stdlib
    certificate decoder instead.
    """
    if not der:
        raise ValueError("服务器未返回证书")
    pem = ssl.DER_cert_to_PEM_cert(der)
    fd, path = tempfile.mkstemp(prefix="node-warden-cert-", suffix=".pem")
    try:
        with os.fdopen(fd, "w", encoding="ascii") as handle:
            handle.write(pem)
        decoder = getattr(ssl._ssl, "_test_decode_cert", None)
        if decoder is None:
            raise ValueError("当前 Python 不支持证书解码")
        return decoder(path)
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass


def certificate_info(domain: str, connect_host: str = "127.0.0.1", connect_port: int = 443) -> dict:
    context = ssl._create_unverified_context()
    try:
        with socket.create_connection((connect_host, int(connect_port)), timeout=5) as sock:
            with context.wrap_socket(sock, server_hostname=domain) as tls:
                der = tls.getpeercert(binary_form=True)
        cert = _decode_certificate(der)
        not_after = cert.get("notAfter", "")
        not_before = cert.get("notBefore", "")
        expires_ts = ssl.cert_time_to_seconds(not_after) if not_after else None
        days = int((expires_ts - time.time()) // 86400) if expires_ts is not None else None
        sans = [value for key, value in cert.get("subjectAltName", ()) if key == "DNS"]
        issuer = ", ".join(f"{key}={value}" for part in cert.get("issuer", ()) for key, value in part)
        subject = ", ".join(f"{key}={value}" for part in cert.get("subject", ()) for key, value in part)
        return {
            "ok": True,
            "domain": domain,
            "not_after": not_after,
            "not_before": not_before,
            "expires_ts": expires_ts,
            "days_remaining": days,
            "sans": sans,
            "issuer": issuer,
            "subject": subject,
            "serial": cert.get("serialNumber", ""),
        }
    except Exception as exc:
        return {"ok": False, "domain": domain, "error": str(exc), "days_remaining": None}


def health_check(health: dict, settings=None) -> dict:
    kind = (health or {}).get("type", "none")
    started = time.monotonic()
    if kind == "none":
        return {"type": kind, "ok": True, "latency_ms": 0, "detail": "未配置健康检查"}
    if kind == "tcp":
        results = [_tcp_check(target) for target in health.get("targets", [])]
        ok = all(item[0] for item in results)
        detail = "; ".join(item[1] for item in results)
    elif kind == "http":
        ok, detail = _http_check(health)
    elif kind == "cert":
        info = certificate_info(health.get("domain", ""), health.get("connect_host", "127.0.0.1"),
                                int(health.get("connect_port", 443)))
        ok = bool(info.get("ok") and (info.get("days_remaining") is None or info["days_remaining"] > 0))
        detail = f"证书剩余 {info.get('days_remaining')} 天" if info.get("ok") else info.get("error", "证书检查失败")
    else:
        ok, detail = False, "未知健康检查类型"
    return {"type": kind, "ok": bool(ok), "latency_ms": int((time.monotonic() - started) * 1000), "detail": detail}


def certbot_dry_run(settings) -> dict:
    cert_name = settings.cert_domain
    result = run([settings.certbot_bin, "renew", "--dry-run", "--no-random-sleep-on-renew",
                  "--cert-name", cert_name], timeout=180)
    return {
        "ok": result.returncode == 0,
        "returncode": result.returncode,
        "output": _text(result, 12000),
        "cert_name": cert_name,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }


_BYTE_UNITS = {
    "b": 1, "kb": 1000, "kib": 1024, "mb": 1000 ** 2, "mib": 1024 ** 2,
    "gb": 1000 ** 3, "gib": 1024 ** 3, "tb": 1000 ** 4, "tib": 1024 ** 4,
}


def _parse_bytes(value) -> int | None:
    text = str(value or "").strip().replace(" ", "")
    match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([A-Za-z]+)?", text)
    if not match:
        return None
    number = float(match.group(1))
    unit = (match.group(2) or "b").lower()
    factor = _BYTE_UNITS.get(unit)
    if factor is None:
        return None
    return int(number * factor)


def _parse_percent(value) -> float | None:
    text = str(value or "").strip().rstrip("%").strip()
    try:
        return round(float(text), 2)
    except ValueError:
        return None


def _parse_io_pair(value) -> tuple[int | None, int | None]:
    parts = str(value or "").split("/", 1)
    first = _parse_bytes(parts[0]) if parts else None
    second = _parse_bytes(parts[1]) if len(parts) > 1 else None
    return first, second


def docker_stats(services: list[dict], settings) -> dict:
    docker_services = [service for service in services if service.get("kind") == "docker"]
    if not docker_services:
        return {}
    result = run([settings.docker_bin, "stats", "--no-stream", "--format", "{{json .}}"], timeout=25)
    if result.returncode != 0:
        return {}
    wanted = {service["target"] for service in docker_services}
    stats = {}
    for line in (result.stdout or "").splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        name = item.get("Name", "")
        if name not in wanted:
            continue
        mem_used, mem_limit = _parse_io_pair(item.get("MemUsage", ""))
        net_rx, net_tx = _parse_io_pair(item.get("NetIO", ""))
        block_read, block_write = _parse_io_pair(item.get("BlockIO", ""))
        stats[name] = {
            "name": name,
            "cpu": item.get("CPUPerc", ""),
            "cpu_percent": _parse_percent(item.get("CPUPerc", "")),
            "memory": item.get("MemUsage", ""),
            "memory_percent": item.get("MemPerc", ""),
            "memory_percent_value": _parse_percent(item.get("MemPerc", "")),
            "memory_used": mem_used,
            "memory_limit": mem_limit,
            "network": item.get("NetIO", ""),
            "network_rx": net_rx,
            "network_tx": net_tx,
            "block": item.get("BlockIO", ""),
            "block_read": block_read,
            "block_write": block_write,
            "pids": item.get("PIDs", ""),
            "pids_count": int(item["PIDs"]) if str(item.get("PIDs", "")).isdigit() else None,
        }
    return stats


def listening_ports() -> list[dict]:
    result = run(["ss", "-H", "-ltnp"], timeout=10)
    if result.returncode != 0:
        return []
    items = []
    for line in (result.stdout or "").splitlines():
        parts = line.split(None, 5)
        if len(parts) < 4:
            continue
        local = parts[3]
        if ":" not in local:
            continue
        host, port_text = local.rsplit(":", 1)
        try:
            port = int(port_text)
        except ValueError:
            continue
        process = ""
        pid = ""
        if len(parts) > 5:
            match = re.search(r'users:\(\("([^"]+)",pid=(\d+)', parts[5])
            if match:
                process, pid = match.group(1), match.group(2)
        items.append({
            "address": host.strip("[]") or "*",
            "port": port,
            "process": process,
            "pid": pid,
            "wildcard": host in {"0.0.0.0", "::", "*"},
        })
    items.sort(key=lambda item: (item["port"], item["address"]))
    return items[:120]


def _cpu_percent() -> float:
    global _CPU_LAST
    try:
        first = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0].split()
        values = [int(value) for value in first[1:]]
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        total = sum(values)
    except (OSError, ValueError, IndexError):
        return 0.0
    lock = _init_lock()
    with lock:
        previous = _CPU_LAST
        _CPU_LAST = (total, idle)
    if previous is None:
        return 0.0
    total_delta = total - previous[0]
    idle_delta = idle - previous[1]
    if total_delta <= 0:
        return 0.0
    return round(max(0.0, min(100.0, (1.0 - idle_delta / total_delta) * 100.0)), 1)


def _memory_info() -> dict:
    values = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            key, raw = line.split(":", 1)
            values[key] = int(raw.strip().split()[0]) * 1024
    except (OSError, ValueError):
        return {"total": 0, "used": 0, "available": 0, "percent": 0}
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", values.get("MemFree", 0))
    used = max(0, total - available)
    return {
        "total": total, "used": used, "available": available,
        "percent": round(used * 100.0 / total, 1) if total else 0,
        "swap_total": values.get("SwapTotal", 0), "swap_used": values.get("SwapTotal", 0) - values.get("SwapFree", 0),
    }


_METRICS_LOCK = None
_METRICS_LAST = None


def _init_metrics_lock():
    global _METRICS_LOCK
    if _METRICS_LOCK is None:
        import threading
        _METRICS_LOCK = threading.Lock()
    return _METRICS_LOCK


def _read_net_dev() -> tuple[int, int, list[dict]]:
    """Return total RX/TX bytes for non-loopback interfaces."""
    total_rx = 0
    total_tx = 0
    interfaces = []
    try:
        lines = Path("/proc/net/dev").read_text(encoding="utf-8").splitlines()[2:]
    except OSError:
        return 0, 0, []
    for line in lines:
        if ":" not in line:
            continue
        name, values = line.split(":", 1)
        name = name.strip()
        fields = values.split()
        if name == "lo" or len(fields) < 10:
            continue
        try:
            rx = int(fields[0])
            tx = int(fields[8])
        except ValueError:
            continue
        total_rx += rx
        total_tx += tx
        if not name.startswith(("docker", "veth", "br-", "virbr")):
            interfaces.append({"name": name, "rx_total": rx, "tx_total": tx})
    interfaces.sort(key=lambda item: item["rx_total"] + item["tx_total"], reverse=True)
    return total_rx, total_tx, interfaces[:8]


_DISK_DEVICE_RE = re.compile(r"^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|nvme\d+n\d+|mmcblk\d+)$")


def _read_disk_io() -> tuple[int, int]:
    """Return total bytes read and written by whole block devices."""
    total_read = 0
    total_write = 0
    try:
        lines = Path("/proc/diskstats").read_text(encoding="utf-8").splitlines()
    except OSError:
        return 0, 0
    for line in lines:
        fields = line.split()
        if len(fields) < 10:
            continue
        name = fields[2]
        if not _DISK_DEVICE_RE.match(name):
            continue
        try:
            total_read += int(fields[5]) * 512
            total_write += int(fields[9]) * 512
        except ValueError:
            continue
    return total_read, total_write


def _read_tcp_connections() -> int:
    count = 0
    for name in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(name).read_text(encoding="utf-8").splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 3 and fields[3] == "01":
                count += 1
    return count


def _count_processes() -> int:
    try:
        return sum(1 for name in os.listdir("/proc") if name.isdigit())
    except OSError:
        return 0


def _top_processes(limit: int = 5) -> list[dict]:
    result = run(["ps", "-eo", "pid,comm,%cpu,%mem", "--sort=-%cpu"], timeout=5)
    if result.returncode != 0:
        return []
    items = []
    for line in (result.stdout or "").splitlines()[1:]:
        parts = line.split(None, 3)
        if len(parts) < 4 or not parts[0].isdigit():
            continue
        try:
            items.append({
                "pid": int(parts[0]),
                "name": parts[1],
                "cpu": round(float(parts[2]), 1),
                "memory": round(float(parts[3]), 1),
            })
        except ValueError:
            continue
        if len(items) >= limit:
            break
    return items


def host_metrics() -> dict:
    """Return live network, disk, connection and process metrics.

    Rates are calculated against the previous call.  The first call after a
    process start reports zero rates rather than a misleading average.
    """
    global _METRICS_LAST
    rx_total, tx_total, interfaces = _read_net_dev()
    read_total, write_total = _read_disk_io()
    now = time.monotonic()
    lock = _init_metrics_lock()
    with lock:
        previous = _METRICS_LAST
        _METRICS_LAST = (now, rx_total, tx_total, read_total, write_total)
    rx_rate = tx_rate = read_rate = write_rate = 0
    if previous is not None:
        elapsed = max(0.001, now - previous[0])
        rx_rate = max(0, int((rx_total - previous[1]) / elapsed))
        tx_rate = max(0, int((tx_total - previous[2]) / elapsed))
        read_rate = max(0, int((read_total - previous[3]) / elapsed))
        write_rate = max(0, int((write_total - previous[4]) / elapsed))
    return {
        "sampled_at": datetime.now(timezone.utc).isoformat(),
        "network": {
            "rx_total": rx_total,
            "tx_total": tx_total,
            "rx_bps": rx_rate,
            "tx_bps": tx_rate,
            "interfaces": interfaces,
        },
        "disk_io": {
            "read_total": read_total,
            "write_total": write_total,
            "read_bps": read_rate,
            "write_bps": write_rate,
        },
        "tcp_connections": _read_tcp_connections(),
        "processes": _count_processes(),
        "top_processes": _top_processes(),
    }


def host_info(settings) -> dict:
    try:
        uptime = float(Path("/proc/uptime").read_text(encoding="utf-8").split()[0])
    except (OSError, ValueError, IndexError):
        uptime = None
    try:
        load = [round(float(item), 2) for item in Path("/proc/loadavg").read_text(encoding="utf-8").split()[:3]]
    except (OSError, ValueError):
        load = []
    os_name = ""
    try:
        for line in Path("/etc/os-release").read_text(encoding="utf-8").splitlines():
            if line.startswith("PRETTY_NAME="):
                os_name = line.split("=", 1)[1].strip().strip('"')
                break
    except OSError:
        pass
    disk = shutil.disk_usage("/")
    data_disk = shutil.disk_usage(settings.data_dir) if Path(settings.data_dir).exists() else None
    return {
        "hostname": socket.gethostname(),
        "os": os_name,
        "kernel": platform.release(),
        "arch": platform.machine(),
        "python": platform.python_version(),
        "now": datetime.now(timezone.utc).isoformat(),
        "uptime_seconds": int(uptime) if uptime is not None else None,
        "load": load,
        "cpu_count": os.cpu_count() or 1,
        "cpu_percent": _cpu_percent(),
        "memory": _memory_info(),
        "disk": {"total": disk.total, "used": disk.used, "free": disk.free,
                 "percent": round(disk.used * 100.0 / disk.total, 1) if disk.total else 0},
        "data_disk": ({"total": data_disk.total, "used": data_disk.used, "free": data_disk.free,
                       "percent": round(data_disk.used * 100.0 / data_disk.total, 1) if data_disk.total else 0}
                      if data_disk else None),
        "metrics": host_metrics(),
    }


# ---------------------------------------------------------------------------
# sing-box inspection


def _load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _config_files(settings) -> list[dict]:
    files = []
    main = settings.singbox_config
    if main.exists():
        files.append({"id": "main", "label": "config.json", "path": str(main),
                      "size": main.stat().st_size, "mtime": int(main.stat().st_mtime)})
    conf_dir = settings.singbox_conf_dir
    if conf_dir.is_dir():
        for path in sorted(conf_dir.glob("*.json")):
            if not path.is_file():
                continue
            files.append({"id": f"conf:{path.name}", "label": path.name, "path": str(path),
                          "size": path.stat().st_size, "mtime": int(path.stat().st_mtime)})
    return files


def _mask_object(value):
    if isinstance(value, dict):
        result = {}
        for key, item in value.items():
            lowered = str(key).lower()
            if lowered in SENSITIVE_KEYS:
                result[key] = MASK
            elif lowered == "users" and isinstance(item, list):
                users = []
                for user in item:
                    if isinstance(user, dict):
                        cleaned = {}
                        for user_key, user_value in user.items():
                            cleaned[user_key] = MASK if str(user_key).lower() in {"password", "uuid", "token", "secret"} else user_value
                        users.append(cleaned)
                    else:
                        users.append(MASK)
                result[key] = users
            else:
                result[key] = _mask_object(item)
        return result
    if isinstance(value, list):
        return [_mask_object(item) for item in value]
    return value


def _inbound_summary(inbound: dict) -> dict:
    tls = inbound.get("tls") or {}
    reality = tls.get("reality") or {}
    transport = inbound.get("transport") or {}
    users = []
    for user in inbound.get("users", []) or []:
        if isinstance(user, dict):
            users.append({
                "username": user.get("username", user.get("name", "")),
                "password": MASK if user.get("password") else "",
            })
    return {
        "tag": inbound.get("tag", ""),
        "type": inbound.get("type", ""),
        "listen": inbound.get("listen", ""),
        "port": inbound.get("listen_port", inbound.get("port")),
        "users": users,
        "transport": transport.get("type", ""),
        "tls": {
            "enabled": bool(tls),
            "server_name": tls.get("server_name", ""),
            "reality": bool(reality),
            "short_id": MASK if reality.get("short_id") else "",
        },
    }


def _find_public_key(value) -> str:
    if isinstance(value, dict):
        for key, item in value.items():
            if str(key).lower() in {"public_key", "publickey"} and isinstance(item, str) and item:
                return item
            if str(key).lower() == "tag" and isinstance(item, str) and item.startswith("public_key_"):
                return item[len("public_key_"):]
            nested = _find_public_key(item)
            if nested:
                return nested
    elif isinstance(value, list):
        for item in value:
            nested = _find_public_key(item)
            if nested:
                return nested
    return ""


def _share_uri(inbound: dict, settings, public_key: str) -> tuple[str | None, list[str]]:
    warnings = []
    host = settings.node_host
    inbound_type = str(inbound.get("type", "")).lower()
    port = inbound.get("listen_port", inbound.get("port"))
    tag = str(inbound.get("tag", "") or inbound_type)
    if not port:
        return None, ["缺少监听端口"]
    tls = inbound.get("tls") or {}
    server_name = str(tls.get("server_name", "") or "")
    if inbound_type == "vless":
        users = inbound.get("users", []) or []
        uuid = next((str(user.get("uuid")) for user in users if isinstance(user, dict) and user.get("uuid")), "")
        if not uuid:
            return None, ["VLESS 入站没有 UUID"]
        if not public_key:
            return None, ["未找到 Reality 公钥，无法生成 VLESS 分享链接"]
        reality = tls.get("reality") or {}
        short_id = str(reality.get("short_id", "") or "")
        transport = inbound.get("transport") or {}
        params = {
            "encryption": "none",
            "security": "reality",
            "sni": server_name or host,
            "fp": "chrome",
            "type": transport.get("type", "tcp"),
            "pbk": public_key,
            "sid": short_id,
        }
        uri = f"vless://{quote(uuid)}@{host}:{port}?{urlencode(params)}#{quote(tag)}"
        return uri, warnings
    if inbound_type == "hysteria2":
        users = inbound.get("users", []) or []
        password = next((str(user.get("password")) for user in users if isinstance(user, dict) and user.get("password")), "")
        if not password:
            return None, ["Hysteria2 入站没有密码"]
        params = {"sni": server_name or host, "insecure": "1"}
        uri = f"hysteria2://{quote(password)}@{host}:{port}/?{urlencode(params)}#{quote(tag)}"
        return uri, warnings
    if inbound_type == "socks":
        users = inbound.get("users", []) or []
        user = next((user for user in users if isinstance(user, dict) and user.get("username")), None)
        if not user:
            return None, ["SOCKS 入站没有用户"]
        uri = f"socks://{quote(str(user.get('username', '')))}:{quote(str(user.get('password', '')))}@{host}:{port}#{quote(tag)}"
        return uri, warnings
    return None, [f"暂不支持为 {inbound_type or 'unknown'} 生成分享链接"]


def _combined_config(settings, main=None) -> dict:
    """Merge the main config with the conf/*.json fragments used by -C.

    The one-click sing-box script keeps each inbound in a separate file below
    /etc/sing-box/conf.  Reading only config.json would hide every inbound, so
    the read-only views merge the fragments while de-duplicating tags.
    """
    main = main if isinstance(main, dict) else (_load_json(settings.singbox_config) or {})
    if not isinstance(main, dict):
        main = {}
    combined = dict(main)
    inbounds = [item for item in (main.get("inbounds") or []) if isinstance(item, dict)]
    outbounds = [item for item in (main.get("outbounds") or []) if isinstance(item, dict)]
    seen_in = {item.get("tag") for item in inbounds if item.get("tag")}
    seen_out = {item.get("tag") for item in outbounds if item.get("tag")}
    if settings.singbox_conf_dir.is_dir():
        for path in sorted(settings.singbox_conf_dir.glob("*.json")):
            fragment = _load_json(path)
            if not isinstance(fragment, dict):
                continue
            for item in fragment.get("inbounds") or []:
                if not isinstance(item, dict):
                    continue
                tag = item.get("tag")
                if tag and tag in seen_in:
                    continue
                if tag:
                    seen_in.add(tag)
                inbounds.append(item)
            for item in fragment.get("outbounds") or []:
                if not isinstance(item, dict):
                    continue
                tag = item.get("tag")
                if tag and tag in seen_out:
                    continue
                if tag:
                    seen_out.add(tag)
                outbounds.append(item)
    combined["inbounds"] = inbounds
    combined["outbounds"] = outbounds
    return combined


def singbox_summary(settings) -> dict:
    installed = bool(settings.singbox_bin and Path(settings.singbox_bin).exists())
    version = ""
    if installed:
        result = run([settings.singbox_bin, "version"], timeout=10)
        version = _text(result, 400).splitlines()[0] if result.stdout else ""
    files = _config_files(settings)
    main = _load_json(settings.singbox_config) if settings.singbox_config.exists() else None
    if main is None:
        return {"installed": installed, "version": version, "files": files,
                "inbounds": [], "outbounds": [], "check": None, "config_ok": False,
                "error": "" if not settings.singbox_config.exists() else "无法读取 sing-box 配置"}
    combined = _combined_config(settings, main)
    check = None
    if installed:
        if files:
            args = [settings.singbox_bin, "check", "-c", str(settings.singbox_config)]
            if settings.singbox_conf_dir.is_dir():
                args += ["-C", str(settings.singbox_conf_dir)]
            result = run(args, timeout=15)
            check = {"ok": result.returncode == 0, "output": _text(result, 4000),
                     "checked_at": datetime.now(timezone.utc).isoformat()}
    return {
        "installed": installed,
        "version": version,
        "files": files,
        "inbounds": [_inbound_summary(item) for item in combined.get("inbounds", []) or [] if isinstance(item, dict)],
        "outbounds": [{"tag": item.get("tag", ""), "type": item.get("type", "")}
                      for item in combined.get("outbounds", []) or [] if isinstance(item, dict)],
        "check": check,
        "config_ok": bool(check and check.get("ok")),
        "log": (combined.get("log") or {}),
    }


def singbox_config_text(settings, file_id: str, reveal: bool = False) -> dict:
    files = _config_files(settings)
    selected = next((item for item in files if item["id"] == file_id), None)
    if selected is None:
        raise ValueError("配置文件不存在")
    path = Path(selected["path"])
    if path.stat().st_size > 512 * 1024:
        raise ValueError("配置文件过大")
    raw = path.read_text(encoding="utf-8")
    if reveal:
        return {"id": file_id, "label": selected["label"], "content": raw, "revealed": True}
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError:
        return {"id": file_id, "label": selected["label"], "content": raw, "revealed": False,
                "warning": "非 JSON 内容，未做敏感字段打码"}
    return {"id": file_id, "label": selected["label"],
            "content": json.dumps(_mask_object(parsed), ensure_ascii=False, indent=2),
            "revealed": False}


def singbox_reveal(settings) -> dict:
    main = _load_json(settings.singbox_config)
    if main is None:
        raise ValueError("无法读取 sing-box 配置")
    combined = _combined_config(settings, main)
    public_key = _find_public_key(combined)
    inbounds = []
    warnings = []
    for inbound in combined.get("inbounds", []) or []:
        if not isinstance(inbound, dict):
            continue
        item = {
            "tag": inbound.get("tag", ""),
            "type": inbound.get("type", ""),
            "listen": inbound.get("listen", ""),
            "port": inbound.get("listen_port", inbound.get("port")),
            "transport": (inbound.get("transport") or {}).get("type", ""),
            "users": inbound.get("users", []) or [],
            "tls": inbound.get("tls", {}) or {},
        }
        uri, item_warnings = _share_uri(inbound, settings, public_key)
        item["share_uri"] = uri
        item["warnings"] = item_warnings
        warnings.extend(item_warnings)
        inbounds.append(item)
    return {
        "host": settings.node_host,
        "inbounds": inbounds,
        "warnings": sorted(set(warnings)),
        "revealed_at": datetime.now(timezone.utc).isoformat(),
    }


# ---------------------------------------------------------------------------
# Fixed actions and logs


def run_service_action(service: dict, action: str, settings) -> dict:
    if action not in service.get("actions", []):
        raise ValueError("该服务不支持此动作")
    kind = service["kind"]
    target = service["target"]
    if kind == "docker":
        if action in {"start", "stop", "restart"}:
            args = [settings.docker_bin, action, target]
        elif action == "test":
            args = [settings.docker_bin, "exec", target, "nginx", "-t"]
        elif action == "reload":
            args = [settings.docker_bin, "exec", target, "nginx", "-s", "reload"]
        else:
            raise ValueError("docker 动作不受支持")
    elif kind == "systemd":
        if action not in {"start", "stop", "restart", "reload"}:
            raise ValueError("systemd 动作不受支持")
        args = [settings.systemctl_bin, action, target]
    elif kind == "singbox":
        if action == "check":
            args = [settings.singbox_bin, "check", "-c", str(settings.singbox_config)]
            if settings.singbox_conf_dir.is_dir():
                args += ["-C", str(settings.singbox_conf_dir)]
        elif action in {"start", "stop", "restart"}:
            args = [settings.systemctl_bin, action, target]
        else:
            raise ValueError("sing-box 动作不受支持")
    else:
        raise ValueError("未知服务类型")
    result = run(args, timeout=60 if action in {"start", "stop", "restart"} else 20)
    return {
        "ok": result.returncode == 0,
        "returncode": result.returncode,
        "action": action,
        "command": args[0],
        "output": _text(result, 8000),
        "at": datetime.now(timezone.utc).isoformat(),
    }


def _tail_text(text: str, tail: int, limit: int = 256 * 1024) -> tuple[str, bool]:
    truncated = len(text) > limit
    text = text[-limit:]
    lines = text.splitlines()
    if len(lines) > tail:
        text = "\n".join(lines[-tail:])
        truncated = True
    return text, truncated


def read_logs(service: dict, source_id: str, tail: int, settings) -> dict:
    source = next((item for item in service.get("logs", []) if item["id"] == source_id), None)
    if source is None:
        raise ValueError("日志源不存在")
    tail = max(10, min(int(tail), settings.max_log_tail))
    truncated = False
    if source["type"] == "docker":
        result = run([settings.docker_bin, "logs", "--timestamps", "--tail", str(tail), source["target"]], timeout=20)
        text = (result.stdout or "") + (result.stderr or "")
        text, truncated = _tail_text(text, tail)
    elif source["type"] == "journal":
        result = run([settings.journalctl_bin, "-u", source["unit"], "-n", str(tail), "--no-pager",
                      "-o", "short-iso"], timeout=20)
        text = (result.stdout or "") + (result.stderr or "")
        text, truncated = _tail_text(text, tail)
    else:
        path = Path(source["path"])
        try:
            data = path.read_bytes()
            text = data[-min(len(data), 256 * 1024):].decode("utf-8", errors="replace")
            text, truncated = _tail_text(text, tail)
        except OSError as exc:
            text = f"cannot read {path}: {exc}"
    return {"source": source_id, "label": source["label"], "text": text, "truncated": truncated}


def _open_url(url: str, timeout: float = 8, headers: dict | None = None, limit: int = 65536) -> dict:
    """Open an http(s) URL without proxy environment variables.

    Returns a small dictionary instead of raising, because every caller is a
    status probe or a diagnostics endpoint that should report a failed edge
    proxy rather than fail the whole panel request.
    """
    context = ssl._create_unverified_context()
    opener = build_opener(ProxyHandler({}), HTTPSHandler(context=context))
    request = Request(url, headers={"User-Agent": "node-warden/probe", **(headers or {})})
    started = time.monotonic()
    try:
        with opener.open(request, timeout=timeout) as response:
            data = response.read(limit)
            elapsed = int((time.monotonic() - started) * 1000)
            return {
                "ok": True, "status": int(response.status), "latency_ms": elapsed,
                "bytes": len(data), "text": data.decode("utf-8", "replace"),
                "error": "",
            }
    except Exception as exc:  # HTTPError carries a status code; network errors do not
        code = getattr(exc, "code", None)
        data = b""
        if code is not None:
            try:
                data = exc.read(limit)
            except Exception:
                data = b""
        elapsed = int((time.monotonic() - started) * 1000)
        return {
            "ok": False, "status": int(code) if code is not None else None,
            "latency_ms": elapsed, "bytes": len(data),
            "text": data.decode("utf-8", "replace"), "error": str(exc),
        }


def _probe_url(url: str, timeout: float = 8, headers: dict | None = None, read_bytes: int = 4096) -> dict:
    result = _open_url(url, timeout=timeout, headers=headers, limit=read_bytes)
    status = result.get("status")
    reachable = status in {200, 206, 301, 302, 400, 401, 403}
    return {
        "ok": reachable,
        "status": status,
        "latency_ms": result.get("latency_ms", 0),
        "bytes": result.get("bytes", 0),
        "speed_bps": int(result.get("bytes", 0) * 1000 / max(1, result.get("latency_ms", 0))),
        "error": "" if reachable else (result.get("error") or "unexpected HTTP status"),
    }


def _fetch_json(url: str, timeout: float = 6) -> tuple[dict | None, str]:
    result = _open_url(url, timeout=timeout, limit=262144)
    if result.get("status") != 200 or not result.get("ok"):
        return None, f"HTTP {result.get('status') or '连接失败'}: {result.get('error', '')}".strip()
    try:
        data = json.loads(result.get("text", ""))
    except (json.JSONDecodeError, TypeError) as exc:
        return None, f"响应不是 JSON: {exc}"
    if not isinstance(data, dict):
        return None, "响应不是 JSON 对象"
    return data, ""


def _parse_gateway_stub(text: str) -> dict:
    active = re.search(r"Active connections:\s*(\d+)", text)
    requests = re.search(r"server accepts handled requests\s*\n\s*(\d+)\s+(\d+)\s+(\d+)", text)
    reading = re.search(r"Reading:\s*(\d+)\s+Writing:\s*(\d+)\s+Waiting:\s*(\d+)", text)
    return {
        "active": int(active.group(1)) if active else None,
        "accepts": int(requests.group(1)) if requests else None,
        "handled": int(requests.group(2)) if requests else None,
        "requests": int(requests.group(3)) if requests else None,
        "reading": int(reading.group(1)) if reading else None,
        "writing": int(reading.group(2)) if reading else None,
        "waiting": int(reading.group(3)) if reading else None,
    }


def _read_tail(path: Path, max_bytes: int = 524288) -> str:
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - max_bytes))
            data = handle.read()
        return data.decode("utf-8", "replace")
    except OSError:
        return ""


_ACCESS_LOG_RE = re.compile(
    r'^(?P<ip>\S+) \S+ \S+ \[[^]]+\] "(?P<method>\S+) (?P<path>[^"]*?) (?:HTTP/[^"]+)?" '
    r'(?P<status>\d{3}) (?P<bytes>\d+|-)'
)


def _parse_access_log(path: Path, prefixes: list[str] | None = None, max_bytes: int = 524288) -> dict:
    """Summarise the tail of an nginx access log without exposing client IPs."""
    text = _read_tail(path, max_bytes)
    lines = [line for line in text.splitlines() if line.strip()]
    counts = {"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0, "other": 0}
    top_paths: dict[str, int] = {}
    total = 0
    total_bytes = 0
    for line in lines:
        match = _ACCESS_LOG_RE.match(line)
        if not match:
            continue
        raw_path = match.group("path")
        path_only = raw_path.split("?", 1)[0]
        if prefixes and not any(path_only.startswith(prefix) for prefix in prefixes):
            continue
        total += 1
        code = match.group("status")
        key = code[0] + "xx" if code[:1] in "2345" else "other"
        counts[key] += 1
        try:
            total_bytes += int(match.group("bytes"))
        except ValueError:
            pass
        top_paths[path_only[:120]] = top_paths.get(path_only[:120], 0) + 1
    top = sorted(top_paths.items(), key=lambda item: item[1], reverse=True)[:8]
    return {
        "available": bool(text),
        "lines": len(lines),
        "requests": total,
        "bytes": total_bytes,
        "status": counts,
        "top_paths": [{"path": path, "requests": count} for path, count in top],
    }


def docker_proxy_status(settings) -> dict:
    endpoint = settings.docker_mirror_url
    probe = _probe_url(endpoint, timeout=8)
    log = _parse_access_log(settings.gateway_access_log, prefixes=["/v2/"])
    return {
        "id": "docker",
        "name": "Docker 镜像代理",
        "kind": "registry-mirror",
        "endpoint": endpoint,
        "probe": probe,
        "stats_ok": log["available"],
        "stats_error": "" if log["available"] else "未找到网关访问日志",
        "traffic": log,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def ghproxy_proxy_status(settings) -> dict:
    stats, stats_error = _fetch_json(settings.ghproxy_stats_url, timeout=5)
    parts = urlsplit(settings.ghproxy_stats_url)
    local_base = parts.scheme + "://" + parts.netloc
    test_url = local_base + "/" + settings.ghproxy_test_url
    probe = _probe_url(test_url, timeout=15,
                       headers={"Range": "bytes=0-65535", "Accept": "*/*"}, read_bytes=65536)
    log = _parse_access_log(settings.gateway_access_log, prefixes=["/https://", "/http://"])
    traffic = log
    if stats:
        traffic = {
            "available": True,
            "requests": stats.get("requests"),
            "bytes": stats.get("bytes"),
            "status": stats.get("status", {}),
            "since": stats.get("since"),
            "errors": stats.get("errors"),
        }
    return {
        "id": "ghproxy",
        "name": "GitHub 下载代理",
        "kind": "http-proxy",
        "endpoint": settings.gateway_url,
        "test_url": test_url,
        "probe": probe,
        "stats_ok": bool(stats),
        "stats_error": stats_error if not stats else "",
        "stats": stats,
        "traffic": traffic,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def gateway_proxy_status(settings) -> dict:
    stats, stats_error = _fetch_json(settings.gateway_status_url, timeout=4)
    stub = {}
    if stats:
        stub = stats.get("stub") or {}
    else:
        result = _open_url(settings.gateway_status_url, timeout=4, limit=4096)
        if result.get("status") == 200:
            stub = _parse_gateway_stub(result.get("text", ""))
            stats_error = ""
        elif not stats_error:
            stats_error = f"HTTP {result.get('status') or '连接失败'}"
    probe = _probe_url(settings.gateway_url, timeout=8)
    log = _parse_access_log(settings.gateway_access_log)
    return {
        "id": "gateway",
        "name": "网关",
        "kind": "nginx-gateway",
        "endpoint": settings.gateway_url,
        "probe": probe,
        "stats_ok": bool(stub),
        "stats_error": stats_error,
        "stub": stub,
        "traffic": log,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def proxy_overview(settings) -> dict:
    return {
        "as_of": datetime.now(timezone.utc).isoformat(),
        "proxies": [
            docker_proxy_status(settings),
            ghproxy_proxy_status(settings),
            gateway_proxy_status(settings),
        ],
    }
