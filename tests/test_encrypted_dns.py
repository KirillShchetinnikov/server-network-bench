"""Offline checks for retry policy, latency ranking and localized output."""

import os
from pathlib import Path
import subprocess
import tempfile
import time
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
check_udp() { fake_check UDP "$1"; }
check_tcp() { fake_check TCP "$1"; }
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
                env={**os.environ, "PROTOCOL": "all", "DNS_LANG": "en", "REPEATS": "1",
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

    def test_protocol_selection_sends_only_selected_queries(self):
        providers = ["One|one.example|https://one.example/dns-query|1.1.1.1,8.8.8.8"]
        for protocol, expected in (("dot", {"DoT"}), ("doh", {"DoH"}),
                                   ("plain", {"UDP", "TCP"}),
                                   ("all", {"DoT", "DoH", "UDP", "TCP"})):
            with self.subTest(protocol=protocol):
                result, counts = self.run_checker(["--protocol", protocol], providers)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual({key.split("-")[0] for key in counts}, expected)
                self.assertTrue(all(count == 2 for count in counts.values()))
                self.assertEqual("TEST-NET control addresses" in result.stdout,
                                 protocol in ("plain", "all"))
                final = result.stdout.split("Available DNS services", 1)[1]
                if protocol == "plain":
                    self.assertNotIn("DoT", final)
                    self.assertNotIn("DoH", final)
                    for address in ("1.1.1.1", "8.8.8.8"):
                        for transport in ("UDP/53", "TCP/53"):
                            self.assertIn(f"{transport}: {address}", final)

    def test_protocol_environment_and_cli_override(self):
        result, counts = self.run_checker(PROTOCOL="doh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(key.startswith("DoH-") for key in counts))
        result, counts = self.run_checker(["--protocol=dot"], PROTOCOL="plain")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all(key.startswith("DoT-") for key in counts))

    def test_plain_only_record_and_unpublished_address(self):
        result, counts = self.run_checker(["--protocol=plain"],
                                         ["Plain|||1.1.1.1", "Encrypted|one.example|"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(counts), 2)
        self.assertIn("no published plain DNS address", result.stdout)
        final = result.stdout.split("Available DNS services", 1)[1]
        self.assertNotIn("Encrypted", final)

    def test_invalid_protocol_and_plain_records_send_no_queries(self):
        for args, providers in ((["--protocol=bad"], PROVIDERS),
                                (["--protocol"], []),
                                ([], ["Bad|||1.1.1.1,"]),
                                ([], ["Bad|||dns.example"]),
                                ([], ["Bad|||1.1.1.1|extra"]),
                                ([], ["Bad|||999.1.1.1"]),
                                ([], ["Bad|||1.1.1.1||"])):
            with self.subTest(args=args, providers=providers):
                result, counts = self.run_checker(args, providers)
                self.assertEqual(result.returncode, 1)
                self.assertFalse(counts)


class PlainProbeTests(unittest.TestCase):
    def run_probe(self, transport="UDP", mode="valid", ip="1.1.1.1"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sitecustomize.py").write_text(r'''import os, socket, struct, time
mode = os.environ.get("PLAIN_MODE")
class FakeSocket:
    def __init__(self, family, kind):
        self.kind = kind
        expected = socket.AF_INET6 if ':' in os.environ['PLAIN_IP'] else socket.AF_INET
        assert family == expected
        self.data = b''
        self.wait = 1
        self.stale = mode == 'stale'
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def settimeout(self, value): self.wait = value
    def connect(self, address):
        assert address == (os.environ['PLAIN_IP'], 53)
        if mode == 'refused': raise ConnectionRefusedError('connection refused')
    def make_response(self, query):
        ident = struct.unpack('!H', query[:2])[0]
        flags = 0x8180
        if mode == 'nxdomain': flags |= 3
        if mode == 'truncated': flags |= 0x0200
        count = 0 if mode == 'empty' else 1
        if mode == 'wrong_id': ident ^= 1
        question = query[12:]
        if mode == 'wrong_question': question = question.replace(b'example', b'invalid')
        if mode == 'not_response': flags &= ~0x8000
        self.data = struct.pack('!6H', ident, flags, 1, count, 0, 0) + question
        if count:
            self.data += b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 60, 4) + b'\x01\x02\x03\x04'
        if mode == 'short_record': self.data = self.data[:-1]
        if mode == 'trailing': self.data += b'junk'
        if self.kind == socket.SOCK_STREAM:
            self.data = struct.pack('!H', len(self.data)) + self.data
    def send(self, query): self.make_response(query); return len(query)
    def sendall(self, query): self.make_response(query[2:])
    def recv(self, size):
        if mode == 'timeout' or mode == 'wrong_id':
            time.sleep(self.wait)
            raise TimeoutError('timed out')
        if mode == 'dribble':
            delay = min(0.04, self.wait)
            time.sleep(delay)
            if delay == self.wait: raise TimeoutError('timed out')
        if self.stale:
            self.stale = False
            ident = struct.unpack('!H', self.data[:2])[0]
            return struct.pack('!H', ident ^ 1) + self.data[2:]
        # Deliberately fragmented TCP messages test recv_exact.
        length = min(size, 1) if self.kind == socket.SOCK_STREAM else size
        chunk, self.data = self.data[:length], self.data[length:]
        return chunk
if mode:
    socket.socket = FakeSocket
''')
            command = PREFIX + f'\ncheck_plain_dns "{ip}" "{transport}"\n'
            started = time.monotonic()
            result = subprocess.run(["bash", "-c", command],
                env={**os.environ, "DNS_LANG": "en", "PROTOCOL": "plain",
                     "TIMEOUT": "0.2", "REPEATS": "0", "TEST_DOMAIN": "Example.COM.",
                     "PLAIN_MODE": mode, "PLAIN_IP": ip, "PYTHONPATH": directory},
                capture_output=True, text=True, timeout=3)
            elapsed = time.monotonic() - started
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout, elapsed

    def test_valid_udp_and_fragmented_tcp_ipv4_and_ipv6(self):
        for transport in ("UDP", "TCP"):
            for ip in ("1.1.1.1", "2001:4860:4860::8888"):
                with self.subTest(transport=transport, ip=ip):
                    output, _ = self.run_probe(transport, ip=ip)
                    self.assertIn(f"OK|{ip} query=", output)
                    self.assertIn("rcode=0 answers=1", output)

    def test_invalid_responses_never_count_as_success(self):
        for mode in ("nxdomain", "empty", "truncated", "wrong_question",
                     "not_response", "short_record", "trailing", "wrong_id", "refused"):
            for transport in ("UDP", "TCP"):
                with self.subTest(mode=mode, transport=transport):
                    output, _ = self.run_probe(transport, mode)
                    self.assertIn("FAIL|", output)
                    self.assertNotIn("OK|", output)

    def test_udp_ignores_stale_id_and_receives_current_response(self):
        output, _ = self.run_probe(mode="stale")
        self.assertIn("OK|", output)

    def test_timeout_and_tcp_dribble_have_one_deadline(self):
        for transport, mode in (("UDP", "timeout"), ("TCP", "dribble")):
            with self.subTest(transport=transport, mode=mode):
                output, elapsed = self.run_probe(transport, mode)
                self.assertIn("FAIL|", output)
                self.assertTrue("timed out" in output or "timeout" in output)
                self.assertLess(elapsed, 1.0, output)


class TimeoutTests(unittest.TestCase):
    def run_probe(self, checker, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            # Эмуляция блокирующего резолвера и медленных сокетов без сети.
            (root / "sitecustomize.py").write_text(r'''
import os, socket, ssl, struct, time
mode = os.environ.get("PROBE_MODE")
def resolve(*args):
    if mode == "resolve":
        time.sleep(5)
        raise socket.gaierror(-3, "Temporary failure in name resolution")
    return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (ip, 853))
            for ip in ("192.0.2.1", "192.0.2.2", "192.0.2.3")]
class SlowSocket:
    def __init__(self, *args): self.wait = 5; self.data = b""
    def settimeout(self, value): self.wait = value
    def delay(self, duration):
        time.sleep(min(duration, self.wait))
        if self.wait <= duration: raise TimeoutError("timed out")
    def connect(self, address):
        if mode == "multiple":
            self.delay(0.12)
            raise ConnectionRefusedError()
    def sendall(self, data):
        question = data[14:]
        response = struct.pack("!6H", 0x1234, 0x8180, 1, 1, 0, 0) + question
        self.data = struct.pack("!H", len(response)) + response
    def recv(self, size):
        self.delay(0.06)
        chunk, self.data = self.data[:1], self.data[1:]
        return chunk
    def close(self): pass
class Context:
    def wrap_socket(self, sock, **kwargs): return sock
if mode in ("resolve", "multiple", "dribble"):
    socket.getaddrinfo = resolve
    socket.socket = SlowSocket
    ssl.create_default_context = Context
''')
            # Медленный curl игнорирует свои параметры --max-time.
            curl = root / "curl"
            curl.write_text("#!/bin/sh\nsleep 5\n")
            curl.chmod(0o755)
            command = PREFIX + f'\n{checker} dns.example\n'
            started = time.monotonic()
            result = subprocess.run(
                ["bash", "-c", command],
                env={**os.environ, "DNS_LANG": "en", "TIMEOUT": "0.2",
                     "TEST_DOMAIN": "example.com", "REPEATS": "0",
                     "PROBE_MODE": mode, "PYTHONPATH": directory,
                     "PATH": directory + os.pathsep + os.environ["PATH"]},
                capture_output=True, text=True, timeout=2,
            )
            elapsed = time.monotonic() - started
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("FAIL|", result.stdout)
        self.assertIn("timeout", result.stdout)
        self.assertNotIn("Killed", result.stderr)
        # Допуск включает запуск Bash и трёх подготовительных Python-процессов.
        self.assertLess(elapsed, 0.9, result.stdout)

    def test_blocking_name_resolution_is_bounded(self):
        self.run_probe("check_dot", "resolve")

    def test_multiple_addresses_share_one_deadline(self):
        self.run_probe("check_dot", "multiple")

    def test_fragmented_response_does_not_reset_deadline(self):
        self.run_probe("check_dot", "dribble")

    def test_hanging_curl_is_bounded(self):
        self.run_probe("check_doh", "curl")


if __name__ == "__main__":
    unittest.main()
