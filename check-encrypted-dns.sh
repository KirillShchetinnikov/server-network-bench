#!/usr/bin/env bash

set -u

# ============================================================
# DoH / DoT connectivity tester
#
# Проверяет реальный DNS-запрос example.com A:
#
#   DoH: RFC 8484, HTTPS/443, application/dns-message
#   DoT: RFC 7858, TLS/TCP/853
#
# Требования:
#   bash
#   curl
#   python3
#
# Запуск:
#   chmod +x check-encrypted-dns.sh
#   ./check-encrypted-dns.sh
#
# ============================================================

TEST_DOMAIN="${TEST_DOMAIN:-example.com}"
TIMEOUT="${TIMEOUT:-5}"

# Формат:
# NAME|DOT_HOST|DOH_URL — любой адрес можно оставить пустым.
# NAME|HOST — DoT на HOST и DoH на https://HOST/dns-query.
# NAME|https://HOST/path — только DoH, без попыток угадать DoT.
# NAME|HOST| — только DoT.
# Можно передать записи аргументами вместо встроенного списка:
# ./check-encrypted-dns.sh 'Google|dns.google' 'AliDNS|https://dns.alidns.com/dns-query'
PROVIDERS=(
    "Yandex|common.dot.dns.yandex.net|https://common.dot.dns.yandex.net/dns-query"
    "Cloudflare|one.one.one.one|https://cloudflare-dns.com/dns-query"
    "Google|dns.google|https://dns.google/dns-query"
    "Quad9|dns.quad9.net|https://dns.quad9.net/dns-query"
    "AdGuard|dns.adguard-dns.com|https://dns.adguard-dns.com/dns-query"
    "Mullvad|dns.mullvad.net|https://dns.mullvad.net/dns-query"
    "CleanBrowsing|security-filter-dns.cleanbrowsing.org|https://doh.cleanbrowsing.org/doh/security-filter/"
    "DNS.SB|dot.sb|https://doh.dns.sb/dns-query"
    "DNSPod|dot.pub|https://dns.pub/dns-query"
    "AliDNS||https://dns.alidns.com/dns-query"
    "360DNS||https://doh.360.cn/dns-query"

    # Ещё 30 сервисов. Адреса сверены с источниками операторов 2026-10-07.
    # DoT оставлен пустым, если источник подтверждает только DoH.
    # https://docs.controld.com/docs/free-dns
    "ControlD|p0.freedns.controld.com|https://freedns.controld.com/p0"
    # https://meta.wikimedia.org/wiki/Wikimedia_DNS
    "Wikimedia|wikimedia-dns.org|https://wikimedia-dns.org/dns-query"
    # https://joindns4.eu/for-public
    "DNS4EU|unfiltered.joindns4.eu|https://unfiltered.joindns4.eu/dns-query"
    # https://umbrella.cisco.com/blog/enhancing-support-dns-encryption-with-dns-over-https
    "OpenDNS|dns.opendns.com|https://dns.opendns.com/dns-query"
    # https://libredns.gr/
    "LibreDNS|dot.libredns.gr|https://doh.libredns.gr/dns-query"
    # https://dnsforge.de/
    "dnsforge|dnsforge.de|https://dnsforge.de/dns-query"
    # https://dnswarden.com/
    "DNSwarden|uncensored.dns.dnswarden.com|https://dns.dnswarden.com/uncensored"
    # https://www.digitale-gesellschaft.ch/dns/
    "DigitaleGesell.|dns.digitale-gesellschaft.ch|https://dns.digitale-gesellschaft.ch/dns-query"
    # https://ffmuc.net/wiki/doku.php?id=knb:dohdot
    "FFMUC|dot.ffmuc.net|https://doh.ffmuc.net/dns-query"
    # https://blog.uncensoreddns.org/dns-servers/
    "UncensoredDNS|anycast.uncensoreddns.org|https://anycast.uncensoreddns.org/dns-query"
    # https://www.fdn.fr/actions/dns/
    "FDN|ns0.fdn.fr|https://ns0.fdn.fr/dns-query"
    # https://rethinkdns.com/configure
    "RethinkDNS||https://sky.bravedns.com/"
    # https://applied-privacy.net/services/dns/
    "AppliedPrivacy|dot1.applied-privacy.net|https://doh.applied-privacy.net/query"
    # https://www.cira.ca/en/how-canadian-shield-works/
    "CIRA|private.canadianshield.cira.ca|https://private.canadianshield.cira.ca/dns-query"
    # https://www.comss.ru/page.php?id=7315
    "Comss.one|dns.comss.one|https://dns.comss.one/dns-query"
    # https://www.nic.cz/odvr/
    "CZ.NIC|odvr.nic.cz|https://odvr.nic.cz/"
    # https://policy.public.dns.iij.jp/
    "IIJ|public.dns.iij.jp|https://public.dns.iij.jp/dns-query"
    # https://restena.lu/en/document/190-configuring-your-server-public-dns-resolver
    "Restena|dnspub.restena.lu|https://dnspub.restena.lu/dns-query"
    # https://portal.switch.ch/pub/public-dns/
    "SWITCH|dns.switch.ch|https://dns.switch.ch/dns-query"
    # https://dns.njal.la/
    "Njalla|dns.njal.la|https://dns.njal.la/dns-query"
    # https://blahdns.com/ — Германия; JP/CH/FI закрыты в 2024 году.
    "BlahDNS-DE|dot-de.blahdns.com|https://doh-de.blahdns.com/dns-query"
    # https://dismail.de/info.html
    "dismail|fdns1.dismail.de|https://fdns1.dismail.de/dns-query"
    # https://openbld.net/
    "OpenBLD||https://ada.openbld.net/dns-query"
    # https://github.com/bebasid/bebasdns
    "BebasDNS|dns.bebasid.com|https://dns.bebasid.com/dns-query"
    # https://dns.digitalsize.net/
    "DigitalSize|dns.digitalsize.net|https://dns.digitalsize.net/dns-query"
    # https://github.com/hagezi/dns-servers/blob/main/CHEATSHEET.md
    "HaGeZi|root.hagezi.org|https://root.hagezi.org/dns-query"
    # https://www.dnscry.pt/public-resolvers/lis01
    "dnscry.pt-Lisbon|lis01.dnscry.pt|https://lis01.dnscry.pt/dns-query"
    # https://dns4all.eu/
    "DNS4all|dot.dns4all.eu|https://doh.dns4all.eu/dns-query"
    # https://www.belnet.be/en/communities-services/all-services/connectivity-and-internet/dns-service/dns-service-technical-faq
    "Belnet||https://dns.belnet.be/dns-query"
    # Презентация CERT-EE: https://ega.ee/wp-content/uploads/2022/11/CERT-EE_introduction_UA.pdf
    "CERT-EE||https://dns.cert.ee/dns-query"
)

if (( $# > 0 )); then
    PROVIDERS=("$@")
fi

parse_provider()
{
    local entry="$1" address
    name="" dot_host="" doh_url=""
    if [[ "$entry" != *'|'* ]]; then
        echo "ERROR: expected NAME|ADDRESS: $entry" >&2
        return 1
    fi
    name="${entry%%|*}"
    address="${entry#*|}"
    if [[ "$address" == *'|'* ]]; then
        IFS='|' read -r dot_host doh_url <<< "$address"
    elif [[ "$address" == https://* ]]; then
        doh_url="$address"
    elif [[ -n "$address" ]]; then
        dot_host="$address"
        doh_url="https://${address}/dns-query"
    fi
    if [[ -z "$name" || ( -z "$dot_host" && -z "$doh_url" ) ||
          "$doh_url" == *'|'* || ( -n "$doh_url" && "$doh_url" != https://* ) ]]; then
        echo "ERROR: invalid provider record: $entry" >&2
        return 1
    fi
}

declare -A PROVIDER_NAMES
for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1
    if [[ -n "${PROVIDER_NAMES[$name]:-}" ]]; then
        echo "ERROR: duplicate provider name: $name" >&2
        exit 1
    fi
    PROVIDER_NAMES["$name"]=1
done

# ------------------------------------------------------------
# Проверка зависимостей
# ------------------------------------------------------------

for cmd in curl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: command '$cmd' not found"
        exit 1
    fi
done

if ! python3 - "$TIMEOUT" <<'PY'
import math
import sys

try:
    timeout = float(sys.argv[1])
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError()
except ValueError:
    print("ERROR: TIMEOUT must be a positive number", file=sys.stderr)
    sys.exit(1)
PY
then
    exit 1
fi

# ------------------------------------------------------------
# Генерация RFC 1035 DNS query:
# example.com A
#
# Результат:
# base64url без "=" для RFC 8484 GET ?dns=
# ------------------------------------------------------------

generate_dns_query()
{
    python3 - "$TEST_DOMAIN" <<'PY'
import base64
import struct
import sys

domain = sys.argv[1].rstrip(".")

# ID = 0x1234
# Flags = RD
header = struct.pack(
    "!HHHHHH",
    0x1234,
    0x0100,
    1,
    0,
    0,
    0
)

qname = b""

for label in domain.split("."):
    encoded = label.encode("idna")
    if not 1 <= len(encoded) <= 63:
        raise ValueError("DNS label length must be between 1 and 63 bytes")
    qname += bytes([len(encoded)]) + encoded

qname += b"\x00"
if len(qname) > 255:
    raise ValueError("DNS name exceeds 255 bytes")

# QTYPE=A
# QCLASS=IN
question = qname + struct.pack("!HH", 1, 1)

packet = header + question

print(
    base64.urlsafe_b64encode(packet)
    .rstrip(b"=")
    .decode()
)
PY
}

DNS_QUERY_B64="$(generate_dns_query)" || exit 1

# ------------------------------------------------------------
# DoH
# ------------------------------------------------------------

check_doh()
{
    local url="$1"

    local tmp_body
    local tmp_headers
    local curl_meta
    local curl_rc

    tmp_body="$(mktemp)"
    tmp_headers="$(mktemp)"

    local separator='?'
    [[ "$url" == *'?'* ]] && separator='&'
    curl_meta="$(
        curl \
            --silent \
            --show-error \
            --location \
            --connect-timeout "$TIMEOUT" \
            --max-time "$TIMEOUT" \
            --header 'Accept: application/dns-message' \
            --dump-header "$tmp_headers" \
            --output "$tmp_body" \
            --write-out '%{http_code}|%{remote_ip}|%{time_connect}|%{time_appconnect}|%{time_total}|%{http_version}|%{time_pretransfer}' \
            "${url}${separator}dns=${DNS_QUERY_B64}" \
            2>/dev/null
    )"

    curl_rc=$?

    if [[ $curl_rc -ne 0 ]]; then
        rm -f "$tmp_body" "$tmp_headers"

        case "$curl_rc" in
            6)
                echo "FAIL|DNS resolve failed"
                ;;
            7)
                echo "FAIL|TCP connect failed"
                ;;
            28)
                echo "FAIL|timeout"
                ;;
            35)
                echo "FAIL|TLS handshake failed"
                ;;
            56)
                echo "FAIL|connection reset"
                ;;
            60)
                echo "FAIL|certificate verify failed"
                ;;
            *)
                echo "FAIL|curl error ${curl_rc}"
                ;;
        esac

        return
    fi

    local http_code
    local remote_ip
    local tcp_time
    local tls_time
    local total_time
    local http_version
    local pretransfer_time

    IFS='|' read -r \
        http_code \
        remote_ip \
        tcp_time \
        tls_time \
        total_time \
        http_version \
        pretransfer_time \
        <<< "$curl_meta"

    if [[ "$http_code" != "200" ]]; then
        rm -f "$tmp_body" "$tmp_headers"

        echo "FAIL|HTTP ${http_code} ${remote_ip}"
        return
    fi

    # Проверяем, что сервер действительно вернул DNS packet,
    # а не HTML/прокси-заглушку.
    local validation

    validation="$(
        python3 - "$tmp_body" "$DNS_QUERY_B64" <<'PY'
import base64
import struct
import sys

path = sys.argv[1]

try:
    data = open(path, "rb").read()

    if len(data) < 12:
        print("INVALID")
        sys.exit()

    (
        transaction_id,
        flags,
        qdcount,
        ancount,
        nscount,
        arcount
    ) = struct.unpack("!HHHHHH", data[:12])

    qr = (flags >> 15) & 1
    rcode = flags & 0x0f
    query = base64.urlsafe_b64decode(sys.argv[2] + "=" * (-len(sys.argv[2]) % 4))

    if transaction_id != 0x1234:
        print("INVALID_ID")
    elif qr != 1:
        print("NOT_RESPONSE")
    elif qdcount != 1 or data[12:len(query)] != query[12:]:
        print("INVALID_QUESTION")
    elif flags & 0x0200 or rcode != 0 or ancount == 0:
        print(f"UNUSABLE rcode={rcode} answers={ancount}")
    else:
        print(f"OK:{rcode}:{ancount}")

except Exception:
    print("INVALID")
PY
    )"

    rm -f "$tmp_body" "$tmp_headers"

    if [[ "$validation" == OK:* ]]; then

        local rcode
        local answers

        IFS=':' read -r _ rcode answers <<< "$validation"

        printf \
            'OK|%s HTTP/%s total=%.0fms query=%.0fms rcode=%s answers=%s\n' \
            "$remote_ip" \
            "$http_version" \
            "$(awk "BEGIN {print $total_time * 1000}")" \
            "$(awk -v total="$total_time" -v ready="$pretransfer_time" 'BEGIN { elapsed = total - ready; print (elapsed > 0 ? elapsed : 0) * 1000 }')" \
            "$rcode" \
            "$answers"
    else
        echo "FAIL|invalid/unusable DNS response: $validation"
    fi
}

# ------------------------------------------------------------
# DoT
# ------------------------------------------------------------

check_dot()
{
    local host="$1"

    python3 - "$host" "$TEST_DOMAIN" "$TIMEOUT" <<'PY'
import socket
import ssl
import struct
import sys
import time

host = sys.argv[1]
domain = sys.argv[2].rstrip(".")
timeout = float(sys.argv[3])

try:
    # --------------------------------------------------------
    # DNS packet
    # --------------------------------------------------------

    header = struct.pack(
        "!HHHHHH",
        0x1234,
        0x0100,
        1,
        0,
        0,
        0
    )

    qname = b""

    for label in domain.split("."):
        encoded = label.encode("idna")
        qname += bytes([len(encoded)]) + encoded

    qname += b"\x00"

    question = qname + struct.pack("!HH", 1, 1)

    dns_packet = header + question

    # RFC 7858:
    # DNS message over TCP имеет 2-byte length prefix
    wire_packet = struct.pack("!H", len(dns_packet)) + dns_packet

    # --------------------------------------------------------
    # Resolve
    # --------------------------------------------------------

    try:
        addresses = socket.getaddrinfo(
            host,
            853,
            socket.AF_INET,
            socket.SOCK_STREAM
        )
    except socket.gaierror as e:
        print(f"FAIL|DNS resolve failed: {e}")
        sys.exit(0)

    last_error = None

    # --------------------------------------------------------
    # Попытка подключения ко всем IPv4 адресам hostname
    # --------------------------------------------------------

    for family, socktype, proto, canonname, sockaddr in addresses:

        ip = sockaddr[0]

        sock = None
        tls = None

        try:
            start = time.monotonic()

            sock = socket.socket(
                family,
                socket.SOCK_STREAM
            )

            sock.settimeout(timeout)

            sock.connect(
                (ip, 853)
            )

            tcp_done = time.monotonic()

            context = ssl.create_default_context()

            tls = context.wrap_socket(
                sock,
                server_hostname=host
            )

            tls_done = time.monotonic()

            # ------------------------------------------------
            # Отправляем настоящий DNS query
            # ------------------------------------------------

            query_start = time.monotonic()
            tls.sendall(wire_packet)

            # Сначала получаем размер DNS message
            length_data = b""

            while len(length_data) < 2:
                chunk = tls.recv(2 - len(length_data))

                if not chunk:
                    raise RuntimeError(
                        "connection closed before DNS response"
                    )

                length_data += chunk

            response_length = struct.unpack(
                "!H",
                length_data
            )[0]

            response = b""

            while len(response) < response_length:
                chunk = tls.recv(
                    response_length - len(response)
                )

                if not chunk:
                    raise RuntimeError(
                        "connection closed during DNS response"
                    )

                response += chunk

            end = time.monotonic()

            if len(response) < 12:
                raise RuntimeError(
                    "invalid DNS response"
                )

            (
                transaction_id,
                flags,
                qdcount,
                ancount,
                nscount,
                arcount
            ) = struct.unpack(
                "!HHHHHH",
                response[:12]
            )

            qr = (flags >> 15) & 1
            rcode = flags & 0x0f

            if transaction_id != 0x1234:
                raise RuntimeError(
                    "invalid DNS transaction ID"
                )

            if qr != 1:
                raise RuntimeError(
                    "packet is not DNS response"
                )

            if qdcount != 1 or response[12:len(dns_packet)] != dns_packet[12:]:
                raise RuntimeError("invalid DNS question")

            if flags & 0x0200 or rcode != 0 or ancount == 0:
                raise RuntimeError(f"unusable DNS response: rcode={rcode} answers={ancount}")

            tcp_ms = (
                tcp_done - start
            ) * 1000

            tls_ms = (
                tls_done - tcp_done
            ) * 1000

            total_ms = (
                end - start
            ) * 1000
            query_ms = (end - query_start) * 1000

            print(
                "OK|"
                f"{ip} "
                f"total={total_ms:.0f}ms "
                f"query={query_ms:.0f}ms "
                f"tcp={tcp_ms:.0f}ms "
                f"tls={tls_ms:.0f}ms "
                f"rcode={rcode} "
                f"answers={ancount}"
            )

            try:
                tls.close()
            except Exception:
                pass

            sys.exit(0)

        except ssl.SSLCertVerificationError as e:
            last_error = (
                f"certificate verify failed: {e}"
            )

        except ssl.SSLError as e:
            last_error = (
                f"TLS handshake failed: {e}"
            )

        except ConnectionRefusedError:
            last_error = (
                f"{ip}:853 connection refused"
            )

        except TimeoutError:
            last_error = (
                f"{ip}:853 timeout"
            )

        except OSError as e:

            if e.errno == 113:
                last_error = (
                    f"{ip}:853 No route to host"
                )

            elif e.errno == 101:
                last_error = (
                    f"{ip}:853 Network unreachable"
                )

            elif e.errno == 104:
                last_error = (
                    f"{ip}:853 connection reset"
                )

            else:
                last_error = (
                    f"{ip}:853 {e}"
                )

        except Exception as e:
            last_error = str(e)

        finally:

            try:
                if tls:
                    tls.close()
            except Exception:
                pass

            try:
                if sock:
                    sock.close()
            except Exception:
                pass

    print(
        "FAIL|" +
        (
            last_error
            if last_error
            else "connection failed"
        )
    )

except Exception as e:
    print(f"FAIL|{e}")
PY
}

# ------------------------------------------------------------
# Проверка прозрачного перехвата обычного DNS (UDP/TCP 53).
# TEST-NET адреса по RFC 5737 не должны обслуживать публичный DNS.
# https://www.rfc-editor.org/rfc/rfc5737#section-4
# ------------------------------------------------------------

check_plain_dns_interception()
{
    python3 - "$TIMEOUT" <<'PY'
import concurrent.futures
import secrets
import socket
import struct
import sys
import time

timeout = float(sys.argv[1])
targets = ("192.0.2.1", "198.51.100.1", "203.0.113.1")


def read_name(data, offset):
    labels, visited, end = [], set(), None
    while True:
        if offset in visited or offset >= len(data):
            raise ValueError("invalid DNS name")
        visited.add(offset)
        size = data[offset]
        if size & 0xc0 == 0xc0:
            if offset + 1 >= len(data):
                raise ValueError("truncated DNS pointer")
            if end is None:
                end = offset + 2
            offset = ((size & 0x3f) << 8) | data[offset + 1]
            continue
        if size & 0xc0:
            raise ValueError("invalid DNS label")
        offset += 1
        if size == 0:
            return b".".join(labels).lower(), end if end is not None else offset
        if offset + size > len(data):
            raise ValueError("truncated DNS label")
        labels.append(data[offset:offset + size])
        offset += size


def validate(data, query_id, domain):
    if len(data) < 12:
        raise ValueError("short DNS response")
    ident, flags, qd, an, ns, ar = struct.unpack("!6H", data[:12])
    if ident != query_id or not flags & 0x8000 or flags & 0x7800 or qd != 1:
        raise ValueError("unrelated DNS response")
    name, offset = read_name(data, 12)
    if name != domain.encode() or data[offset:offset + 4] != struct.pack("!HH", 1, 1):
        raise ValueError("unrelated DNS question")
    offset += 4
    for _ in range(an + ns + ar):
        _, offset = read_name(data, offset)
        if offset + 10 > len(data):
            raise ValueError("truncated DNS record")
        length = struct.unpack("!H", data[offset + 8:offset + 10])[0]
        offset += 10 + length
        if offset > len(data):
            raise ValueError("truncated DNS record data")
    if offset != len(data):
        raise ValueError("trailing DNS data")
    return flags & 15, an


def probe(ip, proto):
    # Уникальное имя в .invalid исключает совпадение со старым ответом.
    domain = secrets.token_hex(12) + ".invalid"
    query_id = secrets.randbelow(65536)
    qname = b"".join(bytes([len(x)]) + x.encode() for x in domain.split(".")) + b"\0"
    query = struct.pack("!6H", query_id, 0x0100, 1, 0, 0, 0) + qname + struct.pack("!HH", 1, 1)
    deadline = time.monotonic() + timeout
    try:
        kind = socket.SOCK_DGRAM if proto == "UDP" else socket.SOCK_STREAM
        with socket.socket(socket.AF_INET, kind) as sock:
            sock.settimeout(timeout)
            sock.connect((ip, 53))

            def recv_exact(size):
                chunks = bytearray()
                while len(chunks) < size:
                    sock.settimeout(max(0.001, deadline - time.monotonic()))
                    chunk = sock.recv(size - len(chunks))
                    if not chunk:
                        raise ValueError("connection closed")
                    chunks.extend(chunk)
                return bytes(chunks)

            if proto == "UDP":
                sock.send(query)
                data = sock.recv(65535)
            else:
                sock.sendall(struct.pack("!H", len(query)) + query)
                size = struct.unpack("!H", recv_exact(2))[0]
                data = recv_exact(size)
            rcode, answers = validate(data, query_id, domain)
            return "INTERCEPTED", f"rcode={rcode} answers={answers}: DNS response from TEST-NET"
    except (socket.timeout, ConnectionRefusedError):
        return "NO_REPLY", "no DNS response"
    except OSError as exc:
        return "INCONCLUSIVE", str(exc)
    except ValueError as exc:
        return "INCONCLUSIVE", str(exc)


jobs = [(ip, proto) for ip in targets for proto in ("UDP", "TCP")]
with concurrent.futures.ThreadPoolExecutor(max_workers=len(jobs)) as pool:
    results = list(pool.map(lambda item: probe(*item), jobs))
for (ip, proto), (status, details) in zip(jobs, results):
    print(f"  {ip:15} {proto}/53 {status:12} {details}")
if any(status == "INTERCEPTED" for status, _ in results):
    print("  Обнаружен признак перехвата/перенаправления незашифрованного DNS.")
else:
    print("  Перехват не обнаружен этим тестом; выборочный перехват не исключён.")
print("  Тест не определяет, кто перенаправляет запросы: провайдер, роутер, VPN или локальное ПО.")
PY
}

# ------------------------------------------------------------
# Цвета
# ------------------------------------------------------------

if [[ -t 1 ]]; then
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    RESET=$'\033[0m'
else
    GREEN=""
    RED=""
    YELLOW=""
    BLUE=""
    RESET=""
fi

print_result()
{
    local proto="$1"
    local provider="$2"
    local result="$3"

    local status="${result%%|*}"
    local details="${result#*|}"

    if [[ "$status" == "OK" ]]; then
        printf \
            "%-16s %-5s ${GREEN}%-7s${RESET} %s\n" \
            "$provider" \
            "$proto" \
            "OK" \
            "$details"
    elif [[ "$status" == "SKIP" ]]; then
        printf "%-16s %-5s ${YELLOW}%-7s${RESET} %s\n" \
            "$provider" "$proto" "SKIP" "$details"
    else
        printf \
            "%-16s %-5s ${RED}%-7s${RESET} %s\n" \
            "$provider" \
            "$proto" \
            "BLOCKED" \
            "$details"
    fi
}

query_time()
{
    local result="$1"
    if [[ "$result" =~ query=([0-9]+)ms ]]; then
        printf '%sms' "${BASH_REMATCH[1]}"
    else
        printf 'n/a'
    fi
}

# ------------------------------------------------------------
# Запуск
# ------------------------------------------------------------

echo
echo "Encrypted DNS connectivity test"
echo "Test query : ${TEST_DOMAIN} A"
echo "Timeout    : ${TIMEOUT}s"
echo

printf "%-16s %-5s %-7s %s\n" \
    "PROVIDER" \
    "PROTO" \
    "STATUS" \
    "DETAILS"

printf '%*s\n' 90 '' | tr ' ' '-'

declare -A DOH_RESULTS
declare -A DOT_RESULTS

for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1

    dot_result="SKIP|not configured"
    [[ -n "$dot_host" ]] && dot_result="$(check_dot "$dot_host")"

    DOT_RESULTS["$name"]="$dot_result"

    print_result \
        "DoT" \
        "$name" \
        "$dot_result"

    doh_result="SKIP|not configured"
    [[ -n "$doh_url" ]] && doh_result="$(check_doh "$doh_url")"

    DOH_RESULTS["$name"]="$doh_result"

    print_result \
        "DoH" \
        "$name" \
        "$doh_result"

done

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

echo
echo "Summary"
printf '%*s\n' 60 '' | tr ' ' '-'

printf "%-16s %-18s %-18s\n" \
    "PROVIDER" \
    "DoT/853" \
    "DoH/443"

for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1

    dot="${DOT_RESULTS[$name]}"
    doh="${DOH_RESULTS[$name]}"

    dot_status="${dot%%|*}"
    doh_status="${doh%%|*}"

    if [[ "$dot_status" == "OK" ]]; then
        dot_display="OK ($(query_time "$dot"))"
    elif [[ "$dot_status" == "SKIP" ]]; then
        dot_display="SKIP"
    else
        dot_display="BLOCKED"
    fi

    if [[ "$doh_status" == "OK" ]]; then
        doh_display="OK ($(query_time "$doh"))"
    elif [[ "$doh_status" == "SKIP" ]]; then
        doh_display="SKIP"
    else
        doh_display="BLOCKED"
    fi

    printf "%-16s %-18s %-18s\n" \
        "$name" \
        "$dot_display" \
        "$doh_display"

done

echo
echo "Interpretation:"
echo "  OK      = TLS verified + DNS query succeeded (rcode=0, answers>0)"
echo "  BLOCKED = failure at DNS/TCP/TLS/HTTP/DNS-response stage"
echo "            A failure alone does not prove intentional blocking."
echo "  SKIP    = protocol address not configured"
echo "  query   = DNS request/response time, excluding connection setup"
echo "  total   = connection setup + DNS request/response time"
echo

echo "Проверка перехвата незашифрованного DNS (UDP/53 и TCP/53)"
check_plain_dns_interception

echo
echo "Доступные DNS, которые можно использовать (на момент проверки):"
available=0
for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1
    if [[ "${DOT_RESULTS[$name]}" == OK\|* ]]; then
        printf '  %-16s DoT: %s (порт 853) — ответ: %s\n' \
            "$name" "$dot_host" "$(query_time "${DOT_RESULTS[$name]}")"
        available=$((available + 1))
    fi
    if [[ "${DOH_RESULTS[$name]}" == OK\|* ]]; then
        printf '  %-16s DoH: %s — ответ: %s\n' \
            "$name" "$doh_url" "$(query_time "${DOH_RESULTS[$name]}")"
        available=$((available + 1))
    fi
done
if (( available == 0 )); then
    echo "  Нет DNS, успешно прошедших проверку."
fi
