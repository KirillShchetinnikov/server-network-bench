#!/usr/bin/env bash
set -uo pipefail

# Run the requested third-party checks one at a time and retain their output.
RUN_TIME=$(date -u +%Y-%m-%d_%H-%M-%S_UTC)
REPORT_DIR=${REPORT_DIR:-"$PWD/reports/$RUN_TIME"}
REPORT_FILE="$REPORT_DIR/server-report-$RUN_TIME.txt"

checks=(ip-region censorcheck-geoblock censorcheck-dpi russian-iperf3 yabs ip-check bench ipquality sysbench-cpu)
selected=()

usage() {
  cat <<'EOF'
Usage: ./run.sh [--only NAME ...] [--list] [--help]

Run all checks by default. --only may be repeated to run selected checks.
Set REPORT_DIR to choose where logs are saved.
The combined report and a short summary are saved in that directory.
EOF
}

check_title() {
  case $1 in
    ip-region) printf 'IP region' ;;
    censorcheck-geoblock) printf 'Censorcheck: геоблок' ;;
    censorcheck-dpi) printf 'Censorcheck: DPI' ;;
    russian-iperf3) printf 'Скорость до российских iPerf3 серверов' ;;
    yabs) printf 'YABS' ;;
    ip-check) printf 'IP.Check.Place' ;;
    bench) printf 'bench.sh' ;;
    ipquality) printf 'IPQuality' ;;
    sysbench-cpu) printf 'sysbench: CPU, один поток' ;;
  esac
}

contains_check() {
  local wanted=$1 item
  for item in "${checks[@]}"; do
    [[ $item == "$wanted" ]] && return 0
  done
  return 1
}

while (($#)); do
  case $1 in
    --list) printf '%s\n' "${checks[@]}"; exit 0 ;;
    --help|-h) usage; exit 0 ;;
    --only)
      if (($# < 2)) || ! contains_check "$2"; then
        printf 'Unknown or missing check after --only: %s\n' "${2:-}" >&2
        exit 2
      fi
      selected+=("$2")
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
WORK_DIR=$(mktemp -d) || exit 2
trap 'rm -rf -- "$WORK_DIR"' EXIT

download() {
  local url=$1 file=$2
  curl --fail --location --silent --show-error --retry 2 --connect-timeout 10 --max-time 120 \
    --output "$file" "$url" && [[ -s $file ]]
}

run_check() {
  local name=$1 url=$2
  shift 2
  local file="$WORK_DIR/$name.sh"
  printf '\n===== %s =====\n' "$name"
  if [[ $name == sysbench-cpu ]]; then
    if ! command -v sysbench >/dev/null 2>&1; then
      printf 'SKIPPED: sysbench is not installed.\n' | tee "$REPORT_DIR/$name.log"
      printf '%s\tSKIPPED\n' "$name" >> "$REPORT_DIR/summary.tsv"
      return
    fi
    sysbench cpu run --threads=1 2>&1 | tee "$REPORT_DIR/$name.log"
  else
    if ! download "$url" "$file"; then
      printf 'FAILED: download from %s\n' "$url" | tee "$REPORT_DIR/$name.log"
      printf '%s\tDOWNLOAD_FAILED\n' "$name" >> "$REPORT_DIR/summary.tsv"
      return
    fi
    bash "$file" "$@" 2>&1 | tee "$REPORT_DIR/$name.log"
  fi
  local result=${PIPESTATUS[0]}
  if ((result == 0)); then
    printf '%s\tOK\n' "$name" >> "$REPORT_DIR/summary.tsv"
  else
    printf '%s\tFAILED(%d)\n' "$name" "$result" >> "$REPORT_DIR/summary.tsv"
  fi
}

printf 'check\tstatus\n' > "$REPORT_DIR/summary.tsv"
printf 'Отчёт: %s\n' "$REPORT_FILE"
for name in "${selected[@]}"; do
  case $name in
    ip-region) run_check "$name" 'https://ipregion.vrnt.xyz' ;;
    censorcheck-geoblock) run_check "$name" 'https://github.com/vernette/censorcheck/raw/master/censorcheck.sh' --mode geoblock ;;
    censorcheck-dpi) run_check "$name" 'https://github.com/vernette/censorcheck/raw/master/censorcheck.sh' --mode dpi ;;
    russian-iperf3) run_check "$name" 'https://github.com/itdoginfo/russian-iperf3-servers/raw/main/speedtest.sh' ;;
    yabs) run_check "$name" 'https://yabs.sh' -4 ;;
    ip-check) run_check "$name" 'https://ip.check.place' -l en ;;
    bench) run_check "$name" 'https://bench.sh' ;;
    ipquality) run_check "$name" 'https://check.place' -EI ;;
    sysbench-cpu) run_check "$name" '' ;;
  esac
done

completed=0
failed=0
skipped=0
{
  printf 'Проверки сервера и сети\n'
  printf 'Дата запуска (UTC): %s\n' "${RUN_TIME//_/ }"
  printf 'Подробные логи: %s\n' "$REPORT_DIR"
  for name in "${selected[@]}"; do
    printf '\n========== %s ==========\n' "$(check_title "$name")"
    cat "$REPORT_DIR/$name.log"
  done
  printf '\n========== КРАТКИЙ ИТОГ ==========\n'
  while IFS=$'\t' read -r name status; do
    [[ $name == check ]] && continue
    case $status in
      OK) result='завершено'; ((completed+=1)) ;;
      SKIPPED) result='пропущено (sysbench не установлен)'; ((skipped+=1)) ;;
      DOWNLOAD_FAILED) result='ошибка загрузки'; ((failed+=1)) ;;
      FAILED\(*\)) result="ошибка выполнения ${status#FAILED}"; ((failed+=1)) ;;
      *) result="$status"; ((failed+=1)) ;;
    esac
    printf '%s — %s\n' "$(check_title "$name")" "$result"
  done < "$REPORT_DIR/summary.tsv"
  printf 'Всего: %d; завершено: %d; ошибок: %d; пропущено: %d.\n' \
    "${#selected[@]}" "$completed" "$failed" "$skipped"
  printf 'Статус «завершено» означает, что команда отработала; оценки и результаты смотрите выше.\n'
} > "$REPORT_FILE"

sed -n '/^========== КРАТКИЙ ИТОГ ==========/,$p' "$REPORT_FILE"
printf 'Полный отчёт: %s\n' "$REPORT_FILE"
((failed == 0))
