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
#   ./check-encrypted-dns.sh --lang en
#   DNS_LANG=en ./check-encrypted-dns.sh
#
# ============================================================

TEST_DOMAIN="${TEST_DOMAIN:-example.com}"
TIMEOUT="${TIMEOUT:-5}"
DNS_LANG="${DNS_LANG:-ru}"

# Перевод применяется только при выводе; внутренние статусы и метрики
# сохраняют одинаковый формат независимо от выбранного языка.
msg()
{
    if [[ "$DNS_LANG" == en ]]; then
        printf '%s' "$2"
    else
        printf '%s' "$1"
    fi
}

status_text()
{
    case "$1" in
        OK) msg 'ДОСТУПЕН' 'OK' ;;
        SKIP) msg 'ПРОПУЩЕН' 'SKIP' ;;
        BLOCKED|FAIL) msg 'НЕДОСТУПЕН' 'BLOCKED' ;;
    esac
}

localize_details()
{
    local details="$1" english russian
    if [[ "$DNS_LANG" == ru ]]; then
        while IFS='|' read -r english russian; do
            details="${details//"$english"/"$russian"}"
        done <<'TRANSLATIONS'
connection closed before DNS response|соединение закрыто до получения DNS-ответа
connection closed during DNS response|соединение закрыто во время получения DNS-ответа
invalid DNS transaction ID|неверный идентификатор DNS-запроса
packet is not DNS response|пакет не является DNS-ответом
invalid/unusable DNS response|некорректный или непригодный DNS-ответ
unusable DNS response|непригодный DNS-ответ
invalid DNS response|некорректный DNS-ответ
invalid DNS question|DNS-вопрос не совпадает с запросом
certificate verify failed|ошибка проверки сертификата
TLS handshake failed|ошибка согласования TLS
DNS resolve failed|не удалось определить IP-адрес
TCP connect failed|не удалось установить TCP-соединение
connection refused|соединение отклонено
connection reset|соединение сброшено
connection failed|не удалось установить соединение
connection closed|соединение закрыто
No route to host|нет маршрута до сервера
Network unreachable|сеть недоступна
Network is unreachable|сеть недоступна
Connection reset by peer|соединение сброшено сервером
Connection refused|соединение отклонено
Connection timed out|время ожидания соединения истекло
timed out|время ожидания истекло
Name or service not known|имя или служба неизвестны
Temporary failure in name resolution|временная ошибка определения IP-адреса
Operation not permitted|операция не разрешена
Permission denied|доступ запрещён
curl error|ошибка curl
timeout|время ожидания истекло
not configured|адрес не указан
INVALID_QUESTION|DNS-вопрос не совпадает с запросом
INVALID_ID|неверный идентификатор DNS-запроса
NOT_RESPONSE|пакет не является DNS-ответом
UNUSABLE|непригодный DNS-ответ
INVALID|некорректный DNS-ответ
invalid DNS name|некорректное DNS-имя
truncated DNS pointer|неполный DNS-указатель
invalid DNS label|некорректная метка DNS-имени
truncated DNS label|неполная метка DNS-имени
short DNS response|слишком короткий DNS-ответ
unrelated DNS response|ответ не соответствует запросу
unrelated DNS question|DNS-вопрос не соответствует запросу
truncated DNS record data|неполные данные DNS-записи
truncated DNS record|неполная DNS-запись
trailing DNS data|лишние данные в DNS-ответе
DNS response from TEST-NET|DNS-ответ от адреса TEST-NET
no DNS response|нет DNS-ответа
INTERCEPTED|ПЕРЕХВАТ
NO_REPLY|НЕТ ОТВЕТА
INCONCLUSIVE|НЕОПРЕДЕЛЁННО
Evidence of interception/redirection of unencrypted DNS detected.|Обнаружен признак перехвата/перенаправления незашифрованного DNS.
No interception detected by this test; selective interception cannot be ruled out.|Перехват не обнаружен этим тестом; выборочный перехват не исключён.
This test cannot identify who redirects queries: ISP, router, VPN or local software.|Тест не определяет, кто перенаправляет запросы: провайдер, роутер, VPN или локальное ПО.
total=|всего=
query=|запрос=
answers=|ответов=
TRANSLATIONS
        while [[ "$details" =~ ([0-9]+)ms ]]; do
            details="${details//"${BASH_REMATCH[0]}"/"${BASH_REMATCH[1]}мс"}"
        done
    fi
    printf '%s\n' "$details"
}

print_help()
{
    msg 'Проверка шифрованного DNS и перехвата обычного DNS' \
        'Encrypted DNS connectivity and plain DNS interception checker'
    printf '\n\n'
    msg 'Запуск: bash check-encrypted-dns.sh [--lang ru|en] ["ИМЯ|АДРЕС" ...]' \
        'Usage: bash check-encrypted-dns.sh [--lang ru|en] ["NAME|ADDRESS" ...]'
    printf '\n\n'
    msg '  --lang ru|en  Язык вывода: русский (по умолчанию) или английский' \
        '  --lang ru|en  Output language: Russian (default) or English'
    printf '\n'
    msg '  -h, --help    Показать справку' '  -h, --help    Show help'
    printf '\n\n'
    msg 'Переменные: DNS_LANG=ru|en, TEST_DOMAIN=example.com, TIMEOUT=5' \
        'Environment: DNS_LANG=ru|en, TEST_DOMAIN=example.com, TIMEOUT=5'
    printf '\n\n'
    msg 'Форматы провайдеров (аргументы заменяют встроенный список):' \
        'Provider formats (arguments replace the built-in list):'
    printf '\n'
    printf '  "Google|dns.google"\n  "DoH only|https://dns.google/dns-query"\n  "DoT only|dns.google|"\n  "Cloudflare|one.one.one.one|https://cloudflare-dns.com/dns-query"\n'
}

CUSTOM_PROVIDERS=()
show_help=false
while (( $# > 0 )); do
    case "$1" in
        --lang)
            if (( $# < 2 )); then
                msg 'Ошибка: после --lang укажите ru или en.' \
                    'Error: --lang requires ru or en.' >&2
                printf '\n' >&2
                exit 1
            fi
            DNS_LANG="$2"
            shift 2
            ;;
        --lang=*) DNS_LANG="${1#*=}"; shift ;;
        -h|--help) show_help=true; shift ;;
        --) shift; CUSTOM_PROVIDERS+=("$@"); break ;;
        -*)
            printf '%s %s\n' "$(msg 'Ошибка: неизвестный параметр' 'Error: unknown option')" "$1" >&2
            exit 1
            ;;
        *) CUSTOM_PROVIDERS+=("$1"); shift ;;
    esac
done

if [[ "$DNS_LANG" != ru && "$DNS_LANG" != en ]]; then
    printf '%s: %s (ru|en)\n' "$(msg 'Ошибка: неподдерживаемый язык' 'Error: unsupported language')" "$DNS_LANG" >&2
    exit 1
fi
export DNS_LANG
if $show_help; then
    print_help
    exit 0
fi

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

if (( ${#CUSTOM_PROVIDERS[@]} > 0 )); then
    PROVIDERS=("${CUSTOM_PROVIDERS[@]}")
fi

parse_provider()
{
    local entry="$1" address
    name="" dot_host="" doh_url=""
    if [[ "$entry" != *'|'* ]]; then
        printf '%s: %s\n' "$(msg 'Ошибка: ожидается ИМЯ|АДРЕС' 'Error: expected NAME|ADDRESS')" "$entry" >&2
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
        printf '%s: %s\n' "$(msg 'Ошибка: некорректная запись провайдера' 'Error: invalid provider record')" "$entry" >&2
        return 1
    fi
}

declare -A PROVIDER_NAMES
for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1
    if [[ -n "${PROVIDER_NAMES[$name]:-}" ]]; then
        printf '%s: %s\n' "$(msg 'Ошибка: повторяющееся имя провайдера' 'Error: duplicate provider name')" "$name" >&2
        exit 1
    fi
    PROVIDER_NAMES["$name"]=1
done

# ------------------------------------------------------------
# Проверка зависимостей
# ------------------------------------------------------------

for cmd in curl python3; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf '%s: %s\n' "$(msg 'Ошибка: команда не найдена' 'Error: command not found')" "$cmd" >&2
        exit 1
    fi
done

if ! python3 - "$TIMEOUT" <<'PY'
import math
import os
import sys

try:
    timeout = float(sys.argv[1])
    if not math.isfinite(timeout) or timeout <= 0:
        raise ValueError()
except ValueError:
    print("Error: TIMEOUT must be a positive number" if os.environ["DNS_LANG"] == "en"
          else "Ошибка: TIMEOUT должен быть положительным числом", file=sys.stderr)
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

if ! DNS_QUERY_B64="$(generate_dns_query 2>/dev/null)"; then
    printf '%s: %s\n' "$(msg 'Ошибка: некорректный TEST_DOMAIN' 'Error: invalid TEST_DOMAIN')" "$TEST_DOMAIN" >&2
    exit 1
fi

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
    print("  Evidence of interception/redirection of unencrypted DNS detected.")
else:
    print("  No interception detected by this test; selective interception cannot be ruled out.")
print("  This test cannot identify who redirects queries: ISP, router, VPN or local software.")
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
    local details color
    details="$(localize_details "${result#*|}")"

    if [[ "$status" == "OK" ]]; then
        color="$GREEN"
    elif [[ "$status" == "SKIP" ]]; then
        color="$YELLOW"
    else
        color="$RED"
    fi
    print_cell "$provider" 18
    print_cell "$proto" 10
    printf '%s' "$color"
    print_cell "$(status_text "$status")" 18
    printf '%s%s\n' "$RESET" "$details"
}

# Дополняем по числу символов, чтобы кириллица не сдвигала столбцы.
print_cell()
{
    local value="$1" width="$2" padding
    padding=$((width - ${#value}))
    (( padding < 1 )) && padding=1
    printf '%s%*s' "$value" "$padding" ''
}

query_time()
{
    local result="$1"
    if [[ "$result" =~ query=([0-9]+)ms ]]; then
        printf '%s%s' "${BASH_REMATCH[1]}" "$(msg 'мс' 'ms')"
    else
        msg 'нет данных' 'n/a'
    fi
}

# ------------------------------------------------------------
# Запуск
# ------------------------------------------------------------

echo
echo "$(msg 'Проверка доступности шифрованного DNS' 'Encrypted DNS connectivity test')"
printf '%s: %s A\n' "$(msg 'Тестовый запрос' 'Test query')" "$TEST_DOMAIN"
printf '%s: %s%s\n' "$(msg 'Время ожидания' 'Timeout')" "$TIMEOUT" "$(msg 'с' 's')"
echo

print_cell "$(msg 'ПРОВАЙДЕР' 'PROVIDER')" 18
print_cell "$(msg 'ПРОТОКОЛ' 'PROTO')" 10
print_cell "$(msg 'СТАТУС' 'STATUS')" 18
printf '%s\n' "$(msg 'ПОДРОБНОСТИ' 'DETAILS')"

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
echo "$(msg 'Сводная таблица' 'Summary')"
printf '%*s\n' 60 '' | tr ' ' '-'

print_cell "$(msg 'ПРОВАЙДЕР' 'PROVIDER')" 18
print_cell 'DoT/853' 26
printf '%s\n' 'DoH/443'

for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1

    dot="${DOT_RESULTS[$name]}"
    doh="${DOH_RESULTS[$name]}"

    dot_status="${dot%%|*}"
    doh_status="${doh%%|*}"

    if [[ "$dot_status" == "OK" ]]; then
        dot_display="$(status_text OK) ($(query_time "$dot"))"
    elif [[ "$dot_status" == "SKIP" ]]; then
        dot_display="$(status_text SKIP)"
    else
        dot_display="$(status_text BLOCKED)"
    fi

    if [[ "$doh_status" == "OK" ]]; then
        doh_display="$(status_text OK) ($(query_time "$doh"))"
    elif [[ "$doh_status" == "SKIP" ]]; then
        doh_display="$(status_text SKIP)"
    else
        doh_display="$(status_text BLOCKED)"
    fi

    print_cell "$name" 18
    print_cell "$dot_display" 26
    printf '%s\n' "$doh_display"

done

echo
echo "$(msg 'Пояснения:' 'Interpretation:')"
echo "$(msg '  ДОСТУПЕН   = TLS-сертификат проверен, DNS-запрос успешен (rcode=0, ответов>0)' '  OK      = TLS verified + DNS query succeeded (rcode=0, answers>0)')"
echo "$(msg '  НЕДОСТУПЕН = ошибка определения IP-адреса, TCP, TLS, HTTP или DNS-ответа' '  BLOCKED = failure at DNS/TCP/TLS/HTTP/DNS-response stage')"
echo "$(msg '               Ошибка сама по себе не доказывает намеренную блокировку.' '            A failure alone does not prove intentional blocking.')"
echo "$(msg '  ПРОПУЩЕН   = адрес протокола не указан' '  SKIP    = protocol address not configured')"
echo "$(msg '  запрос     = время обмена DNS-запросом и ответом без установки соединения' '  query   = DNS request/response time, excluding connection setup')"
echo "$(msg '  всего      = установка соединения и обмен DNS-запросом и ответом' '  total   = connection setup + DNS request/response time')"
echo

echo "$(msg 'Проверка перехвата незашифрованного DNS (UDP/53 и TCP/53)' 'Unencrypted DNS interception test (UDP/53 and TCP/53)')"
localize_details "$(check_plain_dns_interception)"

echo
echo "$(msg 'Доступные DNS, которые можно использовать (на момент проверки):' 'Available DNS services you can use (at the time of this test):')"
available=0
for provider_data in "${PROVIDERS[@]}"; do
    parse_provider "$provider_data" || exit 1
    if [[ "${DOT_RESULTS[$name]}" == OK\|* ]]; then
        printf '  %-16s DoT: %s (%s 853) — %s: %s\n' \
            "$name" "$dot_host" "$(msg 'порт' 'port')" \
            "$(msg 'ответ' 'response')" "$(query_time "${DOT_RESULTS[$name]}")"
        available=$((available + 1))
    fi
    if [[ "${DOH_RESULTS[$name]}" == OK\|* ]]; then
        printf '  %-16s DoH: %s — %s: %s\n' \
            "$name" "$doh_url" "$(msg 'ответ' 'response')" "$(query_time "${DOH_RESULTS[$name]}")"
        available=$((available + 1))
    fi
done
if (( available == 0 )); then
    echo "$(msg '  Нет DNS, успешно прошедших проверку.' '  No DNS services passed the checks.')"
fi
