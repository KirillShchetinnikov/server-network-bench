import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = (Path(__file__).resolve().parents[1] / 'run.sh').read_text()
DISCOVER = SCRIPT[SCRIPT.index('discover_check_ips() {'):SCRIPT.index('# Expand ip-check')]
EXPAND = SCRIPT[SCRIPT.index('expanded_checks=()'):SCRIPT.index('RUN_STARTED=$SECONDS')]


class AddressTests(unittest.TestCase):
    def run_selection(self, addresses, requested=()):
        with tempfile.TemporaryDirectory() as directory:
            tool = Path(directory) / 'ip'
            tool.write_text('#!/bin/sh\nprintf "%s\\n" "$MOCK_ADDRESSES"\n')
            tool.chmod(0o755)
            env = dict(os.environ, PATH=directory + ':' + os.environ['PATH'])
            env['MOCK_ADDRESSES'] = json.dumps([{'addr_info': [{'local': ip} for ip in addresses]}])
            code = 'requested_ips=("$@"); selected=(ip-region ip-check sysbench-cpu)\n'
            code += DISCOVER + EXPAND + '\nprintf "CHECK:%s\\n" "${selected[@]}"'
            return subprocess.run(['bash', '-c', code, 'test', *requested], env=env, capture_output=True, text=True)

    def test_public_addresses_are_separate_and_deduplicated(self):
        result = self.run_selection(['1.1.1.1', '10.0.0.1', '127.0.0.1', 'ff02::1', 'fe80::1', '2001:4860::1', '1.1.1.1'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['CHECK:ip-region', 'CHECK:ip-check@1.1.1.1', 'CHECK:ip-check@2001:4860::1', 'CHECK:sysbench-cpu'])

    def test_requested_ip_limits_selection(self):
        result = self.run_selection(['1.1.1.1', '8.8.8.8'], ['8.8.8.8', '8.8.8.8'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('ip-check@1.1.1.1', result.stdout)
        self.assertEqual(result.stdout.count('ip-check@8.8.8.8'), 1)

    def test_invalid_unassigned_and_private_addresses_are_rejected(self):
        for address in ['invalid', '9.9.9.9', '10.0.0.1']:
            with self.subTest(address=address):
                result = self.run_selection(['1.1.1.1', '10.0.0.1'], [address])
                self.assertEqual(result.returncode, 2)
                self.assertIn('Не удалось выбрать IP', result.stderr)

    def test_nat_fallback(self):
        result = self.run_selection(['10.0.0.1'])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('CHECK:ip-check\n', result.stdout)


if __name__ == '__main__':
    unittest.main()
