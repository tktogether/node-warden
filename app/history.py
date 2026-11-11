"""Small SQLite-backed availability history for Node Warden.

One sample per service per monitor interval is enough for a 24-hour uptime
strip and incident list.  The database lives in the panel data directory and
is pruned automatically.
"""
from __future__ import annotations

import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path


class HistoryStore:
    def __init__(self, path: Path | str, retention_days: int = 7):
        self.path = Path(path)
        self.retention_days = max(1, int(retention_days))
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init()

    @contextmanager
    def _connect(self):
        conn = sqlite3.connect(str(self.path), timeout=10)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def _init(self) -> None:
        with self._connect() as conn:
            conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS samples (
                    ts INTEGER NOT NULL,
                    service_id TEXT NOT NULL,
                    active INTEGER NOT NULL,
                    health_ok INTEGER NOT NULL,
                    latency_ms INTEGER,
                    detail TEXT NOT NULL DEFAULT ''
                )
                """
            )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_samples_service_ts ON samples(service_id, ts)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_samples_ts ON samples(ts)")
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS host_samples (
                    ts INTEGER PRIMARY KEY,
                    cpu REAL,
                    memory_percent REAL,
                    load1 REAL,
                    rx_bps INTEGER,
                    tx_bps INTEGER,
                    disk_read_bps INTEGER,
                    disk_write_bps INTEGER,
                    tcp_connections INTEGER
                )
                """
            )

    def record(self, service_id: str, active: bool, health_ok: bool,
               latency_ms: int | None = None, detail: str = "", ts: int | None = None) -> None:
        now = int(time.time() if ts is None else ts)
        with self._connect() as conn:
            conn.execute(
                "INSERT INTO samples(ts, service_id, active, health_ok, latency_ms, detail) VALUES(?,?,?,?,?,?)",
                (now, service_id, 1 if active else 0, 1 if health_ok else 0,
                 int(latency_ms) if latency_ms is not None else None, str(detail)[:500]),
            )

    def record_host(self, sample: dict, ts: int | None = None) -> None:
        now = int(time.time() if ts is None else ts)
        def number(key, default=None):
            value = sample.get(key, default)
            try:
                return float(value) if value is not None else None
            except (TypeError, ValueError):
                return None
        with self._connect() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO host_samples(
                    ts, cpu, memory_percent, load1, rx_bps, tx_bps,
                    disk_read_bps, disk_write_bps, tcp_connections
                ) VALUES(?,?,?,?,?,?,?,?,?)
                """,
                (
                    now, number("cpu"), number("memory_percent"), number("load1"),
                    int(number("rx_bps", 0) or 0), int(number("tx_bps", 0) or 0),
                    int(number("disk_read_bps", 0) or 0), int(number("disk_write_bps", 0) or 0),
                    int(number("tcp_connections", 0) or 0),
                ),
            )

    def _bucket(self, hours: int, points: int) -> int:
        return max(60, int(hours * 3600 / max(1, points)))

    def host_series(self, hours: int = 24, points: int = 96) -> list[dict]:
        hours = max(1, min(int(hours), 24 * 30))
        bucket = self._bucket(hours, points)
        cutoff = int(time.time()) - hours * 3600
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM host_samples WHERE ts>=? ORDER BY ts ASC LIMIT 200000", (cutoff,)
            ).fetchall()
        grouped = {}
        for row in rows:
            key = int(row["ts"]) // bucket * bucket
            grouped.setdefault(key, []).append(row)
        series = []
        for key in sorted(grouped):
            items = grouped[key]
            def average(name):
                values = [float(item[name]) for item in items if item[name] is not None]
                return round(sum(values) / len(values), 2) if values else None
            series.append({
                "ts": key,
                "cpu": average("cpu"),
                "memory": average("memory_percent"),
                "load1": average("load1"),
                "rx_bps": int(sum(item["rx_bps"] or 0 for item in items) / len(items)),
                "tx_bps": int(sum(item["tx_bps"] or 0 for item in items) / len(items)),
                "disk_read_bps": int(sum(item["disk_read_bps"] or 0 for item in items) / len(items)),
                "disk_write_bps": int(sum(item["disk_write_bps"] or 0 for item in items) / len(items)),
                "tcp_connections": int(sum(item["tcp_connections"] or 0 for item in items) / len(items)),
                "samples": len(items),
            })
        return series[-points:]

    def service_series(self, service_id: str, hours: int = 24, points: int = 96) -> list[dict]:
        hours = max(1, min(int(hours), 24 * 30))
        bucket = self._bucket(hours, points)
        cutoff = int(time.time()) - hours * 3600
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT ts, active, health_ok, latency_ms FROM samples WHERE service_id=? AND ts>=? ORDER BY ts ASC LIMIT 200000",
                (service_id, cutoff),
            ).fetchall()
        grouped = {}
        for row in rows:
            key = int(row["ts"]) // bucket * bucket
            grouped.setdefault(key, []).append(row)
        series = []
        for key in sorted(grouped):
            items = grouped[key]
            up = sum(1 for item in items if item["active"] and item["health_ok"])
            latency = [int(item["latency_ms"]) for item in items if item["latency_ms"] is not None]
            series.append({
                "ts": key,
                "samples": len(items),
                "up": up,
                "pct": round(up * 100.0 / len(items), 2),
                "latency_ms": int(sum(latency) / len(latency)) if latency else None,
            })
        return series[-points:]

    def availability(self, service_id: str, hours: int = 24) -> dict:
        hours = max(1, min(int(hours), 24 * 30))
        cutoff = int(time.time()) - hours * 3600
        with self._connect() as conn:
            rows = conn.execute(
                "SELECT ts, active, health_ok FROM samples WHERE service_id=? AND ts>=? ORDER BY ts ASC",
                (service_id, cutoff),
            ).fetchall()
        if not rows:
            return {
                "samples": 0, "up_samples": 0, "pct": None, "hours": hours,
                "incidents": [], "down_seconds": 0, "last_sample": None,
            }
        state_rows = [(int(r["ts"]), bool(r["active"] and r["health_ok"])) for r in rows]
        up_samples = sum(1 for _, up in state_rows if up)
        pct = round(up_samples * 100.0 / len(state_rows), 2)
        incidents = []
        down_start = None
        for ts, up in state_rows:
            if not up and down_start is None:
                down_start = ts
            elif up and down_start is not None:
                incidents.append({"start": down_start, "end": ts, "seconds": ts - down_start})
                down_start = None
        now = int(time.time())
        if down_start is not None:
            incidents.append({"start": down_start, "end": now, "seconds": max(0, now - down_start), "ongoing": True})
        return {
            "samples": len(state_rows),
            "up_samples": up_samples,
            "pct": pct,
            "hours": hours,
            "incidents": incidents[-20:],
            "down_seconds": sum(item["seconds"] for item in incidents),
            "last_sample": state_rows[-1][0],
        }

    def prune(self) -> int:
        cutoff = int(time.time()) - self.retention_days * 86400
        with self._connect() as conn:
            result = conn.execute("DELETE FROM samples WHERE ts < ?", (cutoff,))
            host_result = conn.execute("DELETE FROM host_samples WHERE ts < ?", (cutoff,))
            return int(result.rowcount or 0) + int(host_result.rowcount or 0)
