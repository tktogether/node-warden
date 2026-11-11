#!/usr/bin/env python3
"""Allow-listed HTTP proxy for GitHub downloads and git over HTTPS.

The proxy only accepts target URLs whose host is github.com or one of the
GitHub content hosts.  It forwards GET, HEAD and POST requests, follows
redirects inside the same allow-list, and keeps byte counters in memory for
the Node Warden proxy page.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import ssl
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urljoin, urlsplit, urlunsplit

ALLOWED_HOSTS = {
    "github.com",
    "api.github.com",
    "codeload.github.com",
    "raw.githubusercontent.com",
    "objects.githubusercontent.com",
    "gist.githubusercontent.com",
    "user-images.githubusercontent.com",
    "avatars.githubusercontent.com",
    "github-releases.githubusercontent.com",
    "release-assets.githubusercontent.com",
}
ALLOWED_SUFFIXES = (".github.com", ".githubusercontent.com")
REDIRECT_CODES = {301, 302, 303, 307, 308}
FORWARD_REQUEST_HEADERS = (
    "Accept",
    "Accept-Language",
    "User-Agent",
    "Range",
    "If-None-Match",
    "If-Modified-Since",
    "Content-Type",
    "Content-Length",
)
FORWARD_RESPONSE_HEADERS = (
    "Content-Type",
    "Content-Length",
    "Content-Encoding",
    "Content-Disposition",
    "Accept-Ranges",
    "Content-Range",
    "ETag",
    "Last-Modified",
    "Cache-Control",
)
MAX_BODY_BYTES = 64 * 1024 * 1024
READ_CHUNK = 64 * 1024

_STATS_LOCK = threading.Lock()
_STATS = {
    "requests": 0,
    "bytes": 0,
    "errors": 0,
    "status": {"2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0, "other": 0},
    "since": datetime.now(timezone.utc).isoformat(),
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def host_allowed(host: str) -> bool:
    host = (host or "").lower().rstrip(".")
    if not host or "/" in host or "\\" in host:
        return False
    if host in ALLOWED_HOSTS:
        return True
    return any(host.endswith(suffix) for suffix in ALLOWED_SUFFIXES)


def parse_target(request_path: str) -> str:
    """Turn /https://github.com/... into a validated absolute URL."""
    if request_path.startswith("/http://"):
        raw = request_path[1:]
    elif request_path.startswith("/https://"):
        raw = request_path[1:]
    else:
        raise ValueError("target must start with /https:// or /http://")
    parsed = urlsplit(raw)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("unsupported scheme")
    if parsed.username or parsed.password:
        raise ValueError("credentials in target are not allowed")
    host = parsed.hostname or ""
    if not host_allowed(host):
        raise ValueError("host is not allowed")
    port = parsed.port
    if parsed.scheme == "http" and port not in (None, 80):
        raise ValueError("unexpected port")
    if parsed.scheme == "https" and port not in (None, 443):
        raise ValueError("unexpected port")
    path = parsed.path or "/"
    return urlunsplit((parsed.scheme, host if port is None else host + ":" + str(port), path, parsed.query, ""))


def _record(status: int | None = None, size: int = 0, error: bool = False) -> None:
    with _STATS_LOCK:
        _STATS["requests"] += 1
        if size:
            _STATS["bytes"] += size
        if error:
            _STATS["errors"] += 1
        if status is not None:
            key = str(status)[0] + "xx" if str(status)[:1] in "2345" else "other"
            _STATS["status"][key] = _STATS["status"].get(key, 0) + 1


def _record_body(size: int) -> None:
    if size <= 0:
        return
    with _STATS_LOCK:
        _STATS["bytes"] += size


def stats_snapshot() -> dict:
    with _STATS_LOCK:
        return {
            "requests": _STATS["requests"],
            "bytes": _STATS["bytes"],
            "errors": _STATS["errors"],
            "status": dict(_STATS["status"]),
            "since": _STATS["since"],
        }


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "NodeWardenGhProxy/1.0"

    def do_GET(self) -> None:  # noqa: N802
        self._handle("GET")

    def do_HEAD(self) -> None:  # noqa: N802
        self._handle("HEAD")

    def do_POST(self) -> None:  # noqa: N802
        self._handle("POST")

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self.send_header("Allow", "GET, HEAD, POST, OPTIONS")
        self.send_header("Content-Length", "0")
        self.send_header("Connection", "close")
        self.end_headers()

    def _handle(self, method: str) -> None:
        if self.path == "/__stats":
            self._send_json(200, stats_snapshot())
            return
        try:
            target = parse_target(self.path)
        except ValueError as exc:
            _record(400, error=True)
            self._send_text(400, str(exc))
            return
        body = b""
        if method == "POST":
            length = self.headers.get("Content-Length")
            try:
                body_size = int(length or "0")
            except ValueError:
                _record(400, error=True)
                self._send_text(400, "invalid Content-Length")
                return
            if body_size < 0 or body_size > MAX_BODY_BYTES:
                _record(413, error=True)
                self._send_text(413, "request body is too large")
                return
            body = self.rfile.read(body_size) if body_size else b""
        connection = None
        try:
            connection, response, current = self._open(target, method, body)
            self._send_response(method, connection, response)
        except Exception as exc:  # network errors must not kill the thread
            _record(502, error=True)
            self.log_message("upstream error: %s", exc)
            try:
                self._send_text(502, "upstream request failed")
            except OSError:
                pass
        finally:
            if connection is not None:
                try:
                    connection.close()
                except OSError:
                    pass

    def _open(self, target: str, method: str, body: bytes):
        current = target
        headers = {}
        for name in FORWARD_REQUEST_HEADERS:
            value = self.headers.get(name)
            if value:
                headers[name] = value
        for _ in range(6):
            parsed = urlsplit(current)
            host = parsed.hostname or ""
            if not host_allowed(host):
                raise ValueError("redirect left the allow-list")
            port = parsed.port or (443 if parsed.scheme == "https" else 80)
            if parsed.scheme == "https":
                connection = http.client.HTTPSConnection(
                    host, port, timeout=40, context=ssl.create_default_context()
                )
            else:
                connection = http.client.HTTPConnection(host, port, timeout=40)
            path = parsed.path or "/"
            if parsed.query:
                path += "?" + parsed.query
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            if response.status in REDIRECT_CODES and response.getheader("Location"):
                location = response.getheader("Location", "")
                connection.close()
                current = urljoin(current, location)
                if method in ("GET", "HEAD"):
                    body = b""
                elif response.status in (301, 302, 303):
                    method = "GET"
                    body = b""
                    headers.pop("Content-Type", None)
                    headers.pop("Content-Length", None)
                continue
            return connection, response, current
        raise ValueError("too many redirects")

    def _send_response(self, method: str, connection, response) -> None:
        self.send_response(response.status)
        for name in FORWARD_RESPONSE_HEADERS:
            value = response.getheader(name)
            if value:
                self.send_header(name, value)
        self.send_header("Connection", "close")
        self.end_headers()
        _record(response.status)
        if method == "HEAD" or response.status in (204, 304):
            return
        sent = 0
        while True:
            chunk = response.read(READ_CHUNK)
            if not chunk:
                break
            self.wfile.write(chunk)
            sent += len(chunk)
            _record_body(len(chunk))

    def _send_json(self, status: int, payload: dict) -> None:
        data = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def _send_text(self, status: int, message: str) -> None:
        data = (message.rstrip() + "\n").encode("utf-8", "replace")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("[ghproxy] " + fmt % args + "\n")


def self_test() -> int:
    assert parse_target("/https://github.com/git/git") == "https://github.com/git/git"
    assert parse_target("/https://raw.githubusercontent.com/git/git/master/README.md")
    assert host_allowed("objects.githubusercontent.com")
    assert not host_allowed("github.com.evil.example")
    assert not host_allowed("evil.example")
    for bad in ("/http://github.com:8080/x", "/https://github.com:8443/x", "/https://user@github.com/x", "/https://evil.example/x", "/x"):
        try:
            parse_target(bad)
        except ValueError:
            pass
        else:
            raise AssertionError("accepted invalid target: " + bad)
    payload = stats_snapshot()
    assert set(payload) == {"requests", "bytes", "errors", "status", "since"}
    print("ghproxy self-test ok")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Node Warden GitHub download proxy")
    parser.add_argument("--host", default=os.environ.get("GH_PROXY_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("GH_PROXY_PORT", "8082")))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    server = ThreadingHTTPServer((args.host, args.port), ProxyHandler)
    server.daemon_threads = True
    print("ghproxy listening on %s:%d" % (args.host, args.port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
