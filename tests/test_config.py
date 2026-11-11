import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from app.config import ConfigError, Settings, load_backups, load_services


class SettingsTests(unittest.TestCase):
    def settings(self, **overrides):
        env = {
            "PANEL_PUBLIC_URL": "https://panel.example.com/warden",
            "PANEL_KEY_SHA256": "a" * 64,
            "PANEL_SESSION_SECRET": "s" * 32,
            "PANEL_BACKUP_ALLOWED_ROOTS": tempfile.gettempdir(),
        }
        env.update(overrides)
        with mock.patch.dict(os.environ, env, clear=True):
            return Settings()

    def test_valid_minimal_settings(self):
        settings = self.settings()
        self.assertEqual(settings.base_path, "/warden")
        self.assertEqual(settings.public_url, "https://panel.example.com/warden")
        self.assertEqual(settings.cert_domain, "panel.example.com")

    def test_public_url_path_must_match_base_path(self):
        with self.assertRaises(ConfigError):
            self.settings(PANEL_PUBLIC_URL="https://panel.example.com/other")

    def test_key_digest_must_be_sha256_hex(self):
        with self.assertRaises(ConfigError):
            self.settings(PANEL_KEY_SHA256="abc")

    def test_session_secret_must_be_long(self):
        with self.assertRaises(ConfigError):
            self.settings(PANEL_SESSION_SECRET="short")


class RegistryTests(unittest.TestCase):
    def write_registry(self, payload):
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8")
        handle.write(json.dumps(payload, ensure_ascii=False))
        handle.close()
        self.addCleanup(lambda: Path(handle.name).unlink(missing_ok=True))
        return Path(handle.name)

    def base_service(self, **overrides):
        service = {
            "id": "demo",
            "name": "Demo",
            "kind": "docker",
            "target": "demo",
            "actions": ["restart"],
        }
        service.update(overrides)
        return service

    def test_load_valid_service(self):
        path = self.write_registry({"services": [self.base_service()]})
        services = load_services(path)
        self.assertEqual(len(services), 1)
        self.assertEqual(services[0]["id"], "demo")
        self.assertEqual(services[0]["actions"], ["restart"])

    def test_nginx_actions_require_nginx_flag(self):
        path = self.write_registry({"services": [self.base_service(actions=["reload"])]})
        with self.assertRaises(ConfigError):
            load_services(path)

    def test_log_file_must_be_below_var_log(self):
        service = self.base_service(logs=[{"id": "bad", "type": "file", "path": "/tmp/app.log"}])
        path = self.write_registry({"services": [service]})
        with self.assertRaises(ConfigError):
            load_services(path)

    def test_backup_path_must_be_inside_allowed_root(self):
        path = self.write_registry({
            "services": [self.base_service()],
            "backups": [{"id": "bad", "label": "Bad", "path": "/root/.ssh"}],
        })
        with self.assertRaises(ConfigError):
            load_backups(path, ("/etc",))


if __name__ == "__main__":
    unittest.main()
