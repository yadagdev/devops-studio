#!/usr/bin/env bash
set -euo pipefail

# ---- config ----
BASE="${BASE:-http://devops-proxy}"
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
  local f prev tag
  f="$(state_file_for "$STATE_DIR" "$key")"
  prev="$(get_state "$f")"
  tag="$(tag_for_key "$key")"

  set_state "$f" "$status"

  # daily系は「okでも毎回notify」(ただしcheck側が1日1回だけ返す前提)
  if is_daily_key "$key"; then
    if [ "$status" = "ok" ]; then
      notify "${tag} ✅ ${key}: ${msg}"
    else
      # dailyでfailが出るのは想定外だけど一応
      notify "${tag} 🚨 ${key} FAILED: ${msg}"
    fi
    return 0
  fi

  # 通常は状態遷移のみ通知
  if [ "$status" = "ok" ] && [ "$prev" = "fail" ]; then
    notify "${tag} ✅ ${key} recovered: ${msg}"
  elif [ "$status" = "fail" ] && [ "$prev" != "fail" ]; then
    notify "${tag} 🚨 ${key} FAILED: ${msg}"
  fi
}

check_http() {
  local fail=0 failed_path=""
  for p in "${CHECK_PATHS[@]}"; do
    if ! curl -fsS "${BASE}${p}" >/dev/null; then
      fail=1; failed_path="$p"; break
    fi
  done

  if [ "$fail" -eq 0 ]; then
    run_check_and_notify "http" "ok" "base=${BASE} paths=${CHECK_PATHS[*]}"
  else
    run_check_and_notify "http" "fail" "base=${BASE} failed=${failed_path}"
  fi
}

check_script() {
  local script="$1"
  local out status key msg
  out="$("$script")" || out="fail|unknown|script_error"
  status="$(echo "$out" | cut -d'|' -f1)"
  key="$(echo "$out" | cut -d'|' -f2)"
  msg="$(echo "$out" | cut -d'|' -f3-)"
  run_check_and_notify "$key" "$status" "$msg"
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
