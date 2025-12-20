#!/usr/bin/env bash
set -euo pipefail

BASE="${BASE:-http://devops-proxy}"

CHECK_PATHS=(
  "/_internal/healthz"
  "/_internal/upstream/delay-api"
)

WEBHOOK_URL="${DISCORD_WEBHOOK_URL:-}"
INTERVAL="${INTERVAL:-60}"

STATE_DIR="${STATE_DIR:-/state}"
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/last_state"   # ok / fail

echo "[monitor] starting. BASE=${BASE} interval=${INTERVAL}s"
printf '[monitor] check: %s\n' "${CHECK_PATHS[@]}"

notify() {
  local msg="$1"
  if [ -z "$WEBHOOK_URL" ]; then
    echo "[monitor] DISCORD_WEBHOOK_URL is empty; skip notify"
    return 0
  fi
  curl -fsS -H 'Content-Type: application/json' \
    -d "{\"content\":\"${msg}\"}" \
    "$WEBHOOK_URL" >/dev/null || true
}

while true; do
  prev="unknown"
  [ -f "$STATE_FILE" ] && prev="$(cat "$STATE_FILE")"

  fail=0
  failed_path=""
  for p in "${CHECK_PATHS[@]}"; do
    if ! curl -fsS "${BASE}${p}" >/dev/null; then
      fail=1
      failed_path="$p"
      break
    fi
  done

  if [ "$fail" -eq 0 ]; then
    echo "ok" > "$STATE_FILE"
    if [ "$prev" = "fail" ]; then
      notify "✅ DevOps-Studio recovered: ${BASE} (paths: ${CHECK_PATHS[*]})"
    fi
  else
    echo "fail" > "$STATE_FILE"
    echo "[monitor] FAILED path=${failed_path}"
    if [ "$prev" != "fail" ]; then
      notify "🚨 DevOps-Studio healthcheck FAILED: ${BASE} (failed: ${failed_path})"
    fi
  fi

  sleep "$INTERVAL"
done
