import unittest

from app.security import (
    LoginLimiter,
    SessionManager,
    client_ip,
    generate_key,
    hash_key,
    key_id_for,
    origin_allowed,
    validate_new_key,
    verify_key,
)


class KeyTests(unittest.TestCase):
    def test_hash_and_verify(self):
        key = generate_key()
        digest = hash_key(key)
        self.assertEqual(len(digest), 64)
        self.assertTrue(verify_key(key, digest))
        self.assertFalse(verify_key(key + "x", digest))
        self.assertEqual(len(key_id_for(digest)), 16)

    def test_validate_new_key(self):
        self.assertIsNone(validate_new_key("x" * 10))
        self.assertIsNotNone(validate_new_key("short"))
        self.assertIsNone(validate_new_key("x" * 24))
        self.assertIsNotNone(validate_new_key("x" * 9))
        self.assertIsNotNone(validate_new_key("x" * 257))
        self.assertIsNotNone(validate_new_key("x" * 12 + " " + "y" * 12))


class SessionTests(unittest.TestCase):
    def test_issue_verify_and_rotate(self):
        manager = SessionManager("s" * 32, 3600, "a" * 16)
        issued = manager.issue(now=1000)
        payload = manager.verify(issued["cookie"], now=1001)
        self.assertIsNotNone(payload)
        self.assertEqual(payload["csrf"], issued["csrf"])
        manager.set_key_id("b" * 16)
        self.assertIsNone(manager.verify(issued["cookie"], now=1002))

    def test_expiry_and_tampering(self):
        manager = SessionManager("s" * 32, 60, "a" * 16)
        issued = manager.issue(now=1000)
        self.assertIsNone(manager.verify(issued["cookie"], now=1061))
        tampered = ("A" if issued["cookie"][0] != "A" else "B") + issued["cookie"][1:]
        self.assertIsNone(manager.verify(tampered, now=1001))


class RequestSafetyTests(unittest.TestCase):
    def test_login_limiter_window(self):
        limiter = LoginLimiter(2, 60)
        self.assertTrue(limiter.allow("203.0.113.9", now=10))
        limiter.failure("203.0.113.9", now=10)
        limiter.failure("203.0.113.9", now=11)
        self.assertFalse(limiter.allow("203.0.113.9", now=12))
        self.assertTrue(limiter.allow("203.0.113.9", now=80))

    def test_client_ip_only_trusts_proxy_from_loopback(self):
        self.assertEqual(client_ip({"X-Real-IP": "203.0.113.9"}, "127.0.0.1"), "203.0.113.9")
        self.assertEqual(client_ip({"X-Real-IP": "203.0.113.9"}, "198.51.100.7"), "198.51.100.7")

    def test_origin_allowlist(self):
        self.assertTrue(origin_allowed(None, "https://panel.example.com", "https://panel.example.com/warden"))
        self.assertTrue(origin_allowed("https://panel.example.com", "https://panel.example.com", "https://panel.example.com/warden"))
        self.assertFalse(origin_allowed("https://evil.example", "https://panel.example.com", "https://panel.example.com/warden"))


if __name__ == "__main__":
    unittest.main()
