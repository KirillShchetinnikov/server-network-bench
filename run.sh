#!/usr/bin/env bash
set -uo pipefail

# Run the requested third-party checks one at a time and retain their output.
RUN_TIME=${BENCH_RUN_TIME:-$(date -u +%Y-%m-%d_%H-%M-%S_UTC)}
REPORT_DIR=${REPORT_DIR:-"$PWD/reports/$RUN_TIME"}
PUBLISHED_URL='https://bench.kipik1.ru/run.sh'
PROJECT_URL='https://github.com/KirillShchetinnikov/server-network-bench'

checks=(ip-region censorcheck-geoblock censorcheck-dpi russian-iperf3 yabs ip-check bench sysbench-cpu)
selected=()
run_mode=background

usage() {
  cat <<'EOF'
Usage: ./run.sh [--only NAME ...] [--background|--foreground] [--list] [--help]

Run all checks in the background by default, continuing after terminal exit.
Use --foreground to keep output in the terminal. --only may be repeated.
Set REPORT_DIR to choose where logs are saved.
Text and Markdown reports, and a short summary, are saved in that directory.
--only ipquality is an alias for --only ip-check.
EOF
}

check_title() {
  case $1 in
    ip-region) printf 'IP region' ;;
    censorcheck-geoblock) printf 'Censorcheck: геоблок' ;;
    censorcheck-dpi) printf 'Censorcheck: DPI' ;;
    russian-iperf3) printf 'Скорость до российских iPerf3 серверов' ;;
    yabs) printf 'YABS' ;;
    ip-check) printf 'IP Quality Check (IP.Check.Place)' ;;
    bench) printf 'bench.sh' ;;
    sysbench-cpu) printf 'sysbench: CPU, один поток' ;;
  esac
}

check_source_url() {
  case $1 in
    ip-region) printf 'https://github.com/vernette/ipregion/blob/master/ipregion.sh' ;;
    censorcheck-geoblock|censorcheck-dpi) printf 'https://github.com/vernette/censorcheck/blob/master/censorcheck.sh' ;;
    russian-iperf3) printf 'https://github.com/itdoginfo/russian-iperf3-servers/blob/main/speedtest.sh' ;;
    yabs) printf 'https://github.com/masonr/yet-another-bench-script/blob/master/yabs.sh' ;;
    ip-check) printf 'https://github.com/xykt/IPQuality/blob/main/ip.sh' ;;
    bench) printf 'https://github.com/teddysun/across/blob/master/bench.sh' ;;
    sysbench-cpu) printf 'https://github.com/akopytov/sysbench' ;;
  esac
}

contains_check() {
  local wanted=$1 item
  [[ $wanted == ipquality ]] && return 0
  for item in "${checks[@]}"; do
    [[ $item == "$wanted" ]] && return 0
  done
  return 1
}

while (($#)); do
  case $1 in
    --list) printf '%s\n' "${checks[@]}"; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    --background) run_mode=background; shift ;;
    --foreground) run_mode=foreground; shift ;;
    --only)
      if (($# < 2)) || ! contains_check "$2"; then
        printf 'Unknown or missing check after --only: %s\n' "${2:-}" >&2
        exit 2
      fi
      requested=$2
      [[ $requested == ipquality ]] && requested=ip-check
      duplicate=0
      for item in "${selected[@]}"; do
        [[ $item == "$requested" ]] && duplicate=1
      done
      ((duplicate == 1)) || selected+=("$requested")
      shift 2
      ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if ((${#selected[@]} == 0)); then selected=("${checks[@]}"); fi
if ! command -v curl >/dev/null 2>&1; then
  printf 'curl is required.\n' >&2
  exit 2
fi

mkdir -p -- "$REPORT_DIR" || exit 2
REPORT_DIR=$(cd -- "$REPORT_DIR" && pwd) || exit 2
REPORT_FILE="$REPORT_DIR/server-report-$RUN_TIME.txt"
REPORT_MD_FILE="$REPORT_DIR/server-report-$RUN_TIME.md"

if [[ $run_mode == background ]]; then
  if ! command -v nohup >/dev/null 2>&1; then
    printf 'nohup is required for background mode. Use --foreground instead.\n' >&2
    exit 2
  fi
  runner="$REPORT_DIR/runner.sh"
  if [[ -f ${BASH_SOURCE[0]} ]]; then
    cp -- "${BASH_SOURCE[0]}" "$runner" || exit 2
  else
    if ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 120 \
      --output "$runner" "$PUBLISHED_URL" || [[ ! -s $runner ]]; then
      printf 'Could not save the script for background execution.\n' >&2
      exit 2
    fi
  fi
  child_args=(--foreground)
  for name in "${selected[@]}"; do child_args+=(--only "$name"); done
  BENCH_RUN_TIME="$RUN_TIME" REPORT_DIR="$REPORT_DIR" \
    nohup bash "$runner" "${child_args[@]}" > "$REPORT_DIR/live-output.log" 2>&1 < /dev/null &
  pid=$!
  printf '%s\n' "$pid" > "$REPORT_DIR/pid"
  printf 'Проект: %s\n' "$PROJECT_URL"
  printf 'Запущено в фоне, PID: %s\n' "$pid"
  printf 'Ход проверок: tail -f %q\n' "$REPORT_DIR/live-output.log"
  printf 'Итоговый отчёт: %s\n' "$REPORT_FILE"
  printf 'Отчёт Markdown: %s\n' "$REPORT_MD_FILE"
  exit 0
fi

if ! WORK_DIR=$(mktemp -d "$PWD/.server-network-bench-work.XXXXXXXX" 2>/dev/null); then
  WORK_DIR=$(mktemp -d) || exit 2
  printf 'Временный каталог создан в %s; тест диска будет измерять эту файловую систему.\n' "$WORK_DIR"
fi
trap 'rm -rf -- "$WORK_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

download() {
  local url=$1 file=$2
  curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 120 \
    --output "$file" "$url" && [[ -s $file ]]
}

format_duration() {
  local seconds=${1:-0}
  printf '%02d:%02d:%02d' "$((seconds / 3600))" "$(((seconds / 60) % 60))" "$((seconds % 60))"
}

record_result() {
  printf '%s\t%s\t%d\n' "$1" "$2" "$((SECONDS - $3))" >> "$REPORT_DIR/summary.tsv"
}

status_label() {
  case $1 in
    OK) printf 'завершено' ;;
    SKIPPED) printf 'пропущено (sysbench не установлен)' ;;
    DOWNLOAD_FAILED) printf 'ошибка загрузки' ;;
    FAILED\(*\)) printf 'ошибка выполнения %s' "${1#FAILED}" ;;
    *) printf '%s' "$1" ;;
  esac
}

markdown_cell() {
  local value=$1
  value=${value//|/\\|}
  value=${value//$'\n'/ }
  printf '%s' "$value"
}

public_ip() {
  local family=$1 url=$2 address
  address=$(curl "-$family" --fail --location --silent --connect-timeout 3 --max-time 6 "$url" 2>/dev/null) || address=
  if [[ $family == 4 && $address =~ ^[0-9]+(\.[0-9]+){3}$ ]] ||
     [[ $family == 6 && $address == *:* && $address != *[[:space:]]* ]]; then
    printf '%s' "$address"
  else
    printf 'н/д'
  fi
}

strip_terminal_controls() {
  local check=$1
  LC_ALL=C sed -u -E $'s/\033\\][^\a\033]*(\a|\033\\\\)//g; s/\033\\[[0-?]*[ -/]*[@-~]//g; s/\033.//g' |
    LC_ALL=C awk -v check="$check" '
      {
        # A carriage return redraws the same terminal line. Keep its final frame.
        count = split($0, frames, "\r")
        line = frames[count]
        gsub(/[\001-\010\013\014\016-\037\177]/, "", line)
        if (count > 1 && line == "") next

        # IP Quality prints a long sponsor animation before the actual report.
        if ((check == "ip-check" || check == "ipquality") && !report_started) {
          if (index(line, "IP QUALITY CHECK REPORT:") > 0) {
            report_started = 1
          } else {
            preamble = preamble line "\n"
            next
          }
        }
        if (check == "russian-iperf3" && line ~ /^Testing .*\.\.\./) next
        if (check == "ip-region" && line ~ /Checking: /) next
        if (check ~ /^censorcheck-/ && line ~ /^\[[0-9]+\/[0-9]+\] Checking:/) next
        if (check == "yabs" && line ~ /^Performing IPv4 iperf3/ && line ~ /\|/)
          sub(/^.*\.\.\./, "", line)
        if (check == "yabs" && line ~ /^Preparing system.*fio Disk Speed Tests/)
          sub(/^.*fio Disk Speed Tests/, "fio Disk Speed Tests", line)
        if (check == "yabs" && line ~ /^Running GB4 benchmark test.*Geekbench 4 Benchmark Test:/)
          sub(/^.*Geekbench 4 Benchmark Test:/, "Geekbench 4 Benchmark Test:", line)
        print line
        fflush()
      }
      END {
        # Preserve diagnostics when IP Quality exits before producing a report.
        if ((check == "ip-check" || check == "ipquality") && !report_started)
          printf "%s", preamble
      }
    '
}

run_check() {
  local name=$1 url=$2
  shift 2
  local check_dir file started=$SECONDS
  check_dir=$(mktemp -d "$WORK_DIR/$name.XXXXXXXX") || exit 2
  file="$check_dir/$name.sh"
  printf '\n===== %s =====\n' "$name"
  if [[ $name == sysbench-cpu ]]; then
    if ! command -v sysbench >/dev/null 2>&1; then
      printf 'SKIPPED: sysbench is not installed.\n' | tee "$REPORT_DIR/$name.log"
      record_result "$name" SKIPPED "$started"
      return
    fi
    (cd -- "$check_dir" && sysbench cpu run --threads=1) 2>&1 | strip_terminal_controls "$name" | tee "$REPORT_DIR/$name.log"
  else
    if ! download "$url" "$file"; then
      printf 'FAILED: download from %s\n' "$url" | tee "$REPORT_DIR/$name.log"
      record_result "$name" DOWNLOAD_FAILED "$started"
      return
    fi
    (cd -- "$check_dir" && bash "$file" "$@") 2>&1 | strip_terminal_controls "$name" | tee "$REPORT_DIR/$name.log"
  fi
  local result=${PIPESTATUS[0]}
  if ((result == 0)); then
    record_result "$name" OK "$started"
  else
    record_result "$name" "FAILED($result)" "$started"
  fi
}

RUN_STARTED=$SECONDS
server_hostname=$(hostname 2>/dev/null) || server_hostname='н/д'
server_os=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-н/д}" )
server_kernel=$(uname -sr 2>/dev/null) || server_kernel='н/д'
server_uptime=$(uptime -p 2>/dev/null) || server_uptime='н/д'
server_local_ips=$(hostname -I 2>/dev/null) || server_local_ips='н/д'
[[ -n $server_local_ips ]] || server_local_ips='н/д'
server_ipv4=$(public_ip 4 'https://api.ipify.org')
server_ipv6=$(public_ip 6 'https://api6.ipify.org')
server_cpu=$(awk -F ': ' '/^model name[[:space:]]*:/ {print $2; exit}' /proc/cpuinfo 2>/dev/null)
[[ -n $server_cpu ]] || server_cpu='н/д'
server_threads=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || server_threads='н/д'
server_memory=$(awk '/^MemTotal:/ {printf "%.1f GiB", $2 / 1048576}' /proc/meminfo 2>/dev/null)
[[ -n $server_memory ]] || server_memory='н/д'
server_disk=$(df -hP "$PWD" 2>/dev/null | awk 'NR == 2 {printf "%s всего, %s занято, %s свободно (%s)", $2, $3, $4, $6}')
[[ -n $server_disk ]] || server_disk='н/д'

printf 'check\tstatus\tduration_seconds\n' > "$REPORT_DIR/summary.tsv"
printf 'Проект: %s\n' "$PROJECT_URL"
printf 'Отчёт: %s\n' "$REPORT_FILE"
printf 'Отчёт Markdown: %s\n' "$REPORT_MD_FILE"
for name in "${selected[@]}"; do
  case $name in
    ip-region) run_check "$name" 'https://ipregion.vrnt.xyz' ;;
    censorcheck-geoblock) run_check "$name" 'https://github.com/vernette/censorcheck/raw/master/censorcheck.sh' --mode geoblock ;;
    censorcheck-dpi) run_check "$name" 'https://github.com/vernette/censorcheck/raw/master/censorcheck.sh' --mode dpi ;;
    russian-iperf3) run_check "$name" 'https://github.com/itdoginfo/russian-iperf3-servers/raw/main/speedtest.sh' ;;
    yabs) run_check "$name" 'https://yabs.sh' -4 ;;
    ip-check) run_check "$name" 'https://ip.check.place' -l en -y ;;
    bench) run_check "$name" 'https://bench.sh' ;;
    sysbench-cpu) run_check "$name" '' ;;
  esac
done

completed=0
failed=0
skipped=0
while IFS=$'\t' read -r name status duration; do
  [[ $name == check ]] && continue
  case $status in
    OK) ((completed+=1)) ;;
    SKIPPED) ((skipped+=1)) ;;
    *) ((failed+=1)) ;;
  esac
done < "$REPORT_DIR/summary.tsv"
total_duration=$((SECONDS - RUN_STARTED))

server_fields=(
  'Имя сервера' "$server_hostname"
  'ОС' "$server_os"
  'Ядро' "$server_kernel"
  'Публичный IPv4' "$server_ipv4"
  'Публичный IPv6' "$server_ipv6"
  'Локальные IP' "$server_local_ips"
  'Uptime на старте' "$server_uptime"
  'Процессор' "$server_cpu"
  'Доступных потоков CPU' "$server_threads"
  'Оперативная память' "$server_memory"
  'Диск рабочего каталога' "$server_disk"
)

{
  printf 'Проверки сервера и сети\n'
  printf 'Проект: %s\n' "$PROJECT_URL"
  printf 'Дата запуска (UTC): %s\n' "${RUN_TIME//_/ }"
  printf '\n========== ЛОГИ ПРОВЕРОК ==========\n'
  for name in "${selected[@]}"; do
    printf '\n========== %s ==========\n' "$(check_title "$name")"
    printf 'GitHub: %s\n' "$(check_source_url "$name")"
    cat "$REPORT_DIR/$name.log"
  done
  printf '\n========== ОБЩИЙ ОТЧЁТ ==========\n'
  printf '\nСервер на момент запуска:\n'
  for ((i=0; i<${#server_fields[@]}; i+=2)); do
    printf '%s: %s\n' "${server_fields[i]}" "${server_fields[i+1]}"
  done
  printf '\nРезультаты проверок:\n'
  while IFS=$'\t' read -r name status duration; do
    [[ $name == check ]] && continue
    printf '%s\n  GitHub: %s\n  Статус: %s; время: %s\n' \
      "$(check_title "$name")" "$(check_source_url "$name")" \
      "$(status_label "$status")" "$(format_duration "$duration")"
  done < "$REPORT_DIR/summary.tsv"
  printf 'Общее время: %s\n' "$(format_duration "$total_duration")"
  printf 'Всего: %d; завершено: %d; ошибок: %d; пропущено: %d.\n' \
    "${#selected[@]}" "$completed" "$failed" "$skipped"
  printf 'Статус «завершено» означает, что команда отработала; оценки и результаты смотрите выше.\n'
} > "$REPORT_FILE"

{
  printf '# Проверки сервера и сети\n\n'
  printf '**Проект:** [GitHub](%s)\n\n' "$PROJECT_URL"
  printf '**Дата запуска (UTC):** %s\n\n' "${RUN_TIME//_/ }"
  printf '## Логи проверок\n'
  for name in "${selected[@]}"; do
    printf '\n### %s\n\n' "$(check_title "$name")"
    printf '[Исходный код на GitHub](%s)\n\n' "$(check_source_url "$name")"
    sed 's/^/    /' "$REPORT_DIR/$name.log"
  done
  printf '\n## Общий отчёт\n\n'
  printf '### Сервер на момент запуска\n\n| Параметр | Значение |\n| --- | --- |\n'
  for ((i=0; i<${#server_fields[@]}; i+=2)); do
    printf '| %s | %s |\n' "${server_fields[i]}" "$(markdown_cell "${server_fields[i+1]}")"
  done
  printf '\n### Результаты проверок\n\n| Проверка | Статус | Время |\n| --- | --- | ---: |\n'
  while IFS=$'\t' read -r name status duration; do
    [[ $name == check ]] && continue
    printf '| [%s](%s) | %s | %s |\n' "$(check_title "$name")" "$(check_source_url "$name")" \
      "$(status_label "$status")" "$(format_duration "$duration")"
  done < "$REPORT_DIR/summary.tsv"
  printf '\n**Общее время:** %s  \n' "$(format_duration "$total_duration")"
  printf '**Всего:** %d; завершено: %d; ошибок: %d; пропущено: %d.\n\n' \
    "${#selected[@]}" "$completed" "$failed" "$skipped"
  printf '> «Завершено» означает, что команда отработала. Оценки и результаты смотрите в логах выше.\n'
} > "$REPORT_MD_FILE"

sed -n '/^========== ОБЩИЙ ОТЧЁТ ==========/,$p' "$REPORT_FILE"
printf 'Полный отчёт: %s\n' "$REPORT_FILE"
printf 'Отчёт Markdown: %s\n' "$REPORT_MD_FILE"
((failed == 0))
