import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def load_ghproxy():
    spec = importlib.util.spec_from_file_location("ghproxy", ROOT / "deploy" / "ghproxy.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class GhProxyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = load_ghproxy()

    def test_allowed_hosts(self):
        self.assertTrue(self.module.host_allowed("github.com"))
        self.assertTrue(self.module.host_allowed("objects.githubusercontent.com"))
        self.assertFalse(self.module.host_allowed("github.com.example.org"))
        self.assertFalse(self.module.host_allowed("evil.example"))

    def test_parse_target(self):
        module = self.module
        self.assertEqual(
            module.parse_target("/https://github.com/git/git"),
            "https://github.com/git/git",
        )
        self.assertEqual(
            module.parse_target("/https://raw.githubusercontent.com/git/git/master/README.md?x=1"),
            "https://raw.githubusercontent.com/git/git/master/README.md?x=1",
        )
        for bad in (
            "/https://evil.example/file",
            "/https://github.com:8443/file",
            "/https://user@github.com/file",
            "/http://github.com:8080/file",
            "/file",
        ):
            with self.assertRaises(ValueError):
                module.parse_target(bad)

    def test_stats_shape(self):
        payload = self.module.stats_snapshot()
        self.assertEqual(
            set(payload),
            {"requests", "bytes", "errors", "status", "since"},
        )
        self.assertEqual(set(payload["status"]), {"2xx", "3xx", "4xx", "5xx", "other"})


if __name__ == "__main__":
    unittest.main()
