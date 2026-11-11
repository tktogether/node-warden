import tempfile
import time
import unittest
from pathlib import Path

from app.history import HistoryStore


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.store = HistoryStore(Path(self.temp.name) / "history.db")

    def test_availability_and_incidents(self):
        now = int(time.time())
        self.store.record("demo", True, True, latency_ms=10, ts=now - 20)
        self.store.record("demo", False, False, detail="down", ts=now - 10)
        data = self.store.availability("demo", hours=1)
        self.assertEqual(data["samples"], 2)
        self.assertEqual(data["up_samples"], 1)
        self.assertEqual(data["pct"], 50.0)
        self.assertEqual(len(data["incidents"]), 1)
        self.assertTrue(data["incidents"][0]["ongoing"])

    def test_host_series(self):
        now = int(time.time())
        self.store.record_host({"cpu": 10.0, "memory_percent": 20.0, "load1": 0.5,
                                "rx_bps": 100, "tx_bps": 200, "tcp_connections": 3}, ts=now - 5)
        self.store.record_host({"cpu": 30.0, "memory_percent": 40.0, "load1": 1.5,
                                "rx_bps": 300, "tx_bps": 400, "tcp_connections": 5}, ts=now)
        series = self.store.host_series(hours=1, points=12)
        self.assertGreaterEqual(len(series), 1)
        latest = series[-1]
        self.assertIsNotNone(latest["cpu"])
        self.assertGreaterEqual(latest["tcp_connections"], 3)

    def test_prune_old_samples(self):
        old = int(time.time()) - 8 * 86400
        self.store.record("demo", True, True, ts=old)
        self.store.record_host({"cpu": 1.0}, ts=old)
        self.assertGreaterEqual(self.store.prune(), 2)
        self.assertEqual(self.store.availability("demo")["samples"], 0)
        self.assertEqual(self.store.host_series(hours=24), [])


if __name__ == "__main__":
    unittest.main()
