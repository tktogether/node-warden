import unittest
from types import SimpleNamespace

from app.server import Handler


class BootstrapRouteTests(unittest.TestCase):
    def test_serves_bundled_bootstrap(self):
        handler = object.__new__(Handler)
        sent = {}

        def send(status, body, content_type):
            sent.update(status=status, body=body, content_type=content_type)

        handler._send_bytes = send
        Handler._serve_bootstrap(handler)
        self.assertEqual(sent["status"], 200)
        self.assertIn(b"Node Warden", sent["body"])
        self.assertIn("shellscript", sent["content_type"])


class SessionPayloadTests(unittest.TestCase):
    def _handler(self):
        handler = object.__new__(Handler)
        handler.app = SimpleNamespace(
            sessions=SimpleNamespace(key_id="a" * 64),
            settings=SimpleNamespace(base_path="/warden"),
        )
        return handler

    def test_verified_session_uses_exp_claim(self):
        payload = Handler._session_payload(
            self._handler(),
            {"v": 1, "iat": 100, "exp": 200, "csrf": "c" * 24, "kid": "a" * 64},
        )
        self.assertEqual(payload["expires_at"], 200)
        self.assertEqual(payload["issued_at"], 100)
        self.assertEqual(payload["csrf"], "c" * 24)
        self.assertTrue(payload["authenticated"])

    def test_issued_session_accepts_expires_at(self):
        payload = Handler._session_payload(
            self._handler(),
            {"cookie": "x.y", "csrf": "d" * 24, "expires_at": 300, "iat": 200},
        )
        self.assertEqual(payload["expires_at"], 300)
        self.assertEqual(payload["issued_at"], 200)


if __name__ == "__main__":
    unittest.main()
