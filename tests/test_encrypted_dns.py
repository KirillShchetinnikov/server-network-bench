"""Offline checks for retry policy, latency ranking and localized output."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check-encrypted-dns.sh"
SOURCE = SCRIPT.read_text()
START = SOURCE.index('echo\necho "$(msg')
PREFIX = SOURCE[:SOURCE.rindex("# Запуск")]
MOCKS = r'''
fake_check() {
    local proto="$1" address="$2" key count=0 latency
    key="${address//[!a-zA-Z0-9]/_}"
    key="$FAKE_STATE/$proto-$key"
    [[ -f "$key" ]] && read -r count < "$key"
    count=$((count + 1))
    printf '%s\n' "$count" > "$key"
    case "$address" in
        *failed*) echo 'FAIL|timeout'; return ;;
        *flaky*)
            if (( count > 1 )); then echo 'FAIL|connection reset'; return; fi
            latency=40 ;;
        *slow*) latency=100; (( count % 2 == 0 )) && latency=300 ;;
        *fast*) latency=250; (( count % 2 == 0 )) && latency=10 ;;
        *) latency=9 ;;
    esac
    printf 'OK|127.0.0.1 query=%sms total=500ms rcode=0 answers=1\n' "$latency"
}
check_dot() { fake_check DoT "$1"; }
check_doh() { fake_check DoH "$1"; }
check_plain_dns_interception() { echo 'NO_REPLY no DNS response'; }
'''
PROVIDERS = [
    "Slow|slow.example|https://slow.example/dns-query",
    "Fast|fast.example|",
    "Failed|failed.example|",
    "Flaky|flaky.example|",
    "Mixed|failed-mixed.example|https://tiny.example/dns-query",
]


class CheckerTests(unittest.TestCase):
    def run_checker(self, args=(), providers=PROVIDERS, **env):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                ["bash", "-c", PREFIX + MOCKS + SOURCE[START:], "checker",
                 *args, *providers],
                env={**os.environ, "DNS_LANG": "en", "REPEATS": "1",
                     "TEST_DOMAIN": "example.com", "TIMEOUT": "1",
                     **env, "FAKE_STATE": directory},
                capture_output=True, text=True, timeout=15,
            )
            counts = {p.name: int(p.read_text()) for p in Path(directory).iterdir()}
        return result, counts

    def test_default_repeat_and_numeric_mean_ranking(self):
        result, counts = self.run_checker()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counts["DoT-failed_example"], 1)
        self.assertEqual(counts["DoT-flaky_example"], 2)
        self.assertEqual(counts["DoT-fast_example"], 2)
        self.assertEqual(counts["DoT-failed_mixed_example"], 1)
        self.assertEqual(counts["DoH-https___tiny_example_dns_query"], 2)
        final = result.stdout.split("Available DNS services", 1)[1]
        self.assertNotIn("Failed", final)
        self.assertNotIn("Flaky", final)
        self.assertLess(final.index("  Mixed "), final.index("  Fast "))
        self.assertLess(final.index("  Fast "), final.index("  Slow "))
        self.assertIn("mean response: 130.0ms; checks: 2/2", final)
        self.assertIn("mean response: 200.0ms; checks: 2/2", final)
        self.assertIn("repeat failed at attempt 2", result.stdout)
        self.assertIn("checks=1/2", result.stdout)

    def test_requested_repeats_stop_on_error(self):
        result, counts = self.run_checker(["--repeats", "3"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counts["DoT-fast_example"], 4)
        self.assertEqual(counts["DoT-failed_example"], 1)
        self.assertEqual(counts["DoT-flaky_example"], 2)
        self.assertIn("checks: 4/4", result.stdout)

    def test_zero_repeats_overrides_environment(self):
        result, counts = self.run_checker(["--repeats=0"], REPEATS="3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(count == 1 for count in counts.values()))
        final = result.stdout.split("Available DNS services", 1)[1]
        self.assertIn("Flaky", final)
        self.assertIn("checks: 1/1", final)

    def test_environment_and_russian_output(self):
        result, counts = self.run_checker(["--lang", "ru"], REPEATS="2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counts["DoT-fast_example"], 3)
        self.assertIn("среднее=170.0мс проверок=3/3", result.stdout)
        self.assertIn("ошибка повторной проверки на попытке 2", result.stdout)
        self.assertNotIn("repeat failed", result.stdout)

    def test_empty_final_list(self):
        result, counts = self.run_checker(providers=["Failed|failed.example|"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(counts["DoT-failed_example"], 1)
        self.assertIn("No DNS services passed the checks.", result.stdout)

    def test_invalid_repeat_values_do_not_send_queries(self):
        for args in (["--repeats", "-1"], ["--repeats=1.5"],
                     ["--repeats=abc"], ["--repeats=999999999999999999999"]):
            with self.subTest(args=args):
                result, counts = self.run_checker(args)
                self.assertEqual(result.returncode, 1)
                self.assertIn("REPEATS must", result.stderr)
                self.assertFalse(counts)


if __name__ == "__main__":
    unittest.main()
