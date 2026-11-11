import unittest
from types import SimpleNamespace

from app.server import Handler, PanelApp


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

    def test_serves_bundled_toolbox(self):
        handler = object.__new__(Handler)
        sent = {}

        def send(status, body, content_type):
            sent.update(status=status, body=body, content_type=content_type)

        handler._send_bytes = send
        Handler._serve_toolbox(handler)
        self.assertEqual(sent["status"], 200)
        self.assertIn(b"Node Warden Toolbox", sent["body"])
        self.assertIn("shellscript", sent["content_type"])


class CnSetupInfoTests(unittest.TestCase):
    def _app(self, services):
        app = object.__new__(PanelApp)
        app.settings = SimpleNamespace(
            public_url="https://panel.example.com/warden",
            node_host="panel.example.com",
        )
        app.services = services
        return app

    def test_command_includes_available_proxies(self):
        info = PanelApp.cn_setup_info(self._app([
            {"id": "node-warden-crproxy"},
            {"id": "node-warden-ghproxy"},
        ]))
        self.assertEqual(info["domain"], "panel.example.com")
        self.assertEqual(info["origin"], "https://panel.example.com")
        self.assertEqual(info["script_url"], "https://panel.example.com/warden/bootstrap.sh")
        self.assertEqual(info["toolbox_url"], "https://panel.example.com/warden/toolbox.sh")
        self.assertEqual(info["docker_mirror"], "https://panel.example.com")
        self.assertEqual(info["git_mirror"], "https://panel.example.com")
        self.assertIn("--docker-mirror https://panel.example.com", info["command"])
        self.assertIn("--git-mirror https://panel.example.com", info["command"])
        self.assertIn("--yes --non-interactive", info["command"])

    def test_command_omits_missing_proxies(self):
        info = PanelApp.cn_setup_info(self._app([]))
        self.assertEqual(info["docker_mirror"], "")
        self.assertEqual(info["git_mirror"], "")
        self.assertNotIn("--docker-mirror", info["command"])
        self.assertNotIn("--git-mirror", info["command"])


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
