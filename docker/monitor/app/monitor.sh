#!/usr/bin/env bash
set -euo pipefail

# ---- config ----
BASE="${BASE:-http://devops-proxy:18080}"
STATE_DIR="${STATE_DIR:-/state}"
INTERVAL="${INTERVAL:-60}"

CHECK_PATHS=(
  "/_internal/healthz"
  "/_internal/upstream/delay-api"
)

DISK_EVERY="${DISK_CHECK_EVERY_SEC:-300}"
CERT_EVERY="${CERT_CHECK_EVERY_SEC:-21600}"
BACKUP_EVERY="${BACKUP_CHECK_EVERY_SEC:-3600}"

mkdir -p "$STATE_DIR"

# libs
source /app/lib/notify.sh
source /app/lib/state.sh

echo "[monitor] starting. BASE=${BASE} interval=${INTERVAL}s"

tag_for_key() {
  local key="$1"
  case "$key" in
    http) echo "[health]" ;;
    disk) echo "[disk]" ;;
    cert) echo "[cert]" ;;
    backup|backup_daily) echo "[backup]" ;;
    *) echo "[monitor]" ;;
  esac
}

is_daily_key() {
  [[ "$1" == *_daily ]]
}

run_check_and_notify() {
  local key="$1" status="$2" msg="$3"
  local tag
  tag="$(tag_for_key "$key")"

  # daily系：stateを触らない（状態遷移に影響させない）
  # さらに通知は増やさない方針なので、dailyは明示ONのときだけ通知
  if is_daily_key "$key"; then
    if [ "${BACKUP_DAILY_SUMMARY:-0}" = "1" ]; then
      if [ "$status" = "ok" ]; then
        notify "${tag} 📝 ${key}: ${msg}"
      else
        notify "${tag} 🚨 ${key} FAILED: ${msg}"
      fi
    fi
    return 0
  fi

  local f prev
  f="$(state_file_for "$STATE_DIR" "$key")"
  prev="$(get_state "$f")"
  set_state "$f" "$status"

  # 通常は状態遷移のみ通知
  if [ "$status" = "ok" ] && [ "$prev" = "fail" ]; then
    notify "${tag} ✅ ${key} recovered: ${msg}"
  elif [ "$status" = "fail" ] && [ "$prev" != "fail" ]; then
    notify "${tag} 🚨 ${key} FAILED: ${msg}"
  fi
}

check_http() {
  local fail=0
  local detail=""
  local p code total

  for p in "${CHECK_PATHS[@]}"; do
    # 200以外は失敗扱い（301などもfail）
    code="$(
      curl -sS \
        --connect-timeout 2 --max-time 5 \
        -o /dev/null \
        -w "%{http_code} %{time_total}" \
        "${BASE}${p}" \
      || echo "000 0"
    )"

    # "200 0.012" みたいな形式
    total="$(echo "$code" | awk '{print $2}')"
    code="$(echo "$code"  | awk '{print $1}')"

    if [ "$code" != "200" ]; then
      fail=1
      detail="failed=${p} code=${code} total=${total} base=${BASE}"
      break
    fi
  done

  if [ "$fail" -eq 0 ]; then
    run_check_and_notify "http" "ok" "base=${BASE} paths=${CHECK_PATHS[*]}"
  else
    run_check_and_notify "http" "fail" "${detail}"
  fi
}

check_script() {
  local script="$1"
  local out
  out="$("$script")" || out="fail|unknown|script_error"

  # ★複数行対応：1行ずつ処理
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local status key msg
    status="$(echo "$line" | cut -d'|' -f1)"
    key="$(echo "$line" | cut -d'|' -f2)"
    msg="$(echo "$line" | cut -d'|' -f3-)"
    run_check_and_notify "$key" "$status" "$msg"
  done <<< "$out"
}

# 初回実行
next_disk=0
next_cert=0
next_backup=0

while true; do
  now="$(date +%s)"

  check_http

  if [ "$now" -ge "$next_disk" ]; then
    check_script /app/checks/check_disk.sh
    next_disk=$(( now + DISK_EVERY ))
  fi

  if [ "$now" -ge "$next_cert" ]; then
    check_script /app/checks/check_cert.sh
    next_cert=$(( now + CERT_EVERY ))
  fi

  if [ "$now" -ge "$next_backup" ]; then
    check_script /app/checks/check_backup.sh
    next_backup=$(( now + BACKUP_EVERY ))
  fi

  sleep "$INTERVAL"
done
