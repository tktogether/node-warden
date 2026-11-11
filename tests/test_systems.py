import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from app import systems


class MetricParseTests(unittest.TestCase):
    def test_parse_bytes(self):
        self.assertEqual(systems._parse_bytes('15.53MiB'), int(15.53 * 1024 ** 2))
        self.assertEqual(systems._parse_bytes('1.5kB'), 1500)
        self.assertEqual(systems._parse_bytes('0B'), 0)
        self.assertIsNone(systems._parse_bytes('--'))

    def test_parse_percent(self):
        self.assertEqual(systems._parse_percent('3.42%'), 3.42)
        self.assertIsNone(systems._parse_percent(''))

    def test_parse_io_pair(self):
        self.assertEqual(systems._parse_io_pair('1MiB / 2MiB'), (1048576, 2097152))
        self.assertEqual(systems._parse_io_pair('0B / 0B'), (0, 0))


class AccessLogTests(unittest.TestCase):
    def test_summary_filters_paths(self):
        lines = [
            '1.2.3.4 - - [11/Nov/2026:10:00:00 +0000] "GET /v2/ HTTP/1.1" 401 12 "-" "docker/29"',
            '1.2.3.4 - - [11/Nov/2026:10:00:01 +0000] "GET /v2/library/ubuntu/blobs/sha256:abc HTTP/1.1" 200 1024 "-" "docker/29"',
            '1.2.3.4 - - [11/Nov/2026:10:00:02 +0000] "GET /https://github.com/x/y HTTP/1.1" 200 54 "-" "curl/8"',
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'access.log'
            path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            docker = systems._parse_access_log(path, prefixes=['/v2/'])
            self.assertEqual(docker['requests'], 2)
            self.assertEqual(docker['bytes'], 1036)
            self.assertEqual(docker['status']['4xx'], 1)
            self.assertEqual(docker['status']['2xx'], 1)
            self.assertEqual(docker['top_paths'][0]['requests'], 1)
            github = systems._parse_access_log(path, prefixes=['/https://'])
            self.assertEqual(github['requests'], 1)
            self.assertEqual(github['bytes'], 54)

    def test_parse_stub(self):
        body = ('Active connections: 2 \n'
                'server accepts handled requests\n'
                ' 10 10 20 \n'
                'Reading: 0 Writing: 1 Waiting: 1 \n')
        stub = systems._parse_gateway_stub(body)
        self.assertEqual(stub['active'], 2)
        self.assertEqual(stub['accepts'], 10)
        self.assertEqual(stub['requests'], 20)
        self.assertEqual(stub['writing'], 1)


class ActionTests(unittest.TestCase):
    def test_systemd_reload_uses_systemctl_reload(self):
        service = {'kind': 'systemd', 'target': 'nginx.service', 'actions': ['reload']}
        completed = subprocess.CompletedProcess(['systemctl', 'reload', 'nginx.service'], 0, '', '')
        with mock.patch.object(systems, 'run', return_value=completed) as run:
            result = systems.run_service_action(service, 'reload', SimpleNamespace(systemctl_bin='systemctl'))
        self.assertEqual(run.call_args.args[0], ['systemctl', 'reload', 'nginx.service'])
        self.assertTrue(result['ok'])
        self.assertEqual(result['action'], 'reload')


class SingBoxTests(unittest.TestCase):
    def test_absent_singbox_has_no_error(self):
        settings = SimpleNamespace(
            singbox_bin='/nonexistent/node-warden-sing-box',
            singbox_config=Path('/nonexistent/node-warden/config.json'),
            singbox_conf_dir=Path('/nonexistent/node-warden/conf'),
        )
        result = systems.singbox_summary(settings)
        self.assertFalse(result['installed'])
        self.assertEqual(result['error'], '')
        self.assertEqual(result['inbounds'], [])


class ProbeTests(unittest.TestCase):
    def test_http_400_is_reachable(self):
        result = {'ok': False, 'status': 400, 'latency_ms': 12, 'bytes': 0, 'text': '', 'error': 'HTTP Error 400'}
        with mock.patch.object(systems, '_open_url', return_value=result):
            probe = systems._probe_url('https://gateway.example/')
        self.assertTrue(probe['ok'])
        self.assertEqual(probe['status'], 400)
        self.assertEqual(probe['error'], '')


if __name__ == '__main__':
    unittest.main()
