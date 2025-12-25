#!/usr/bin/env bash
set -euo pipefail

NOTIFY_DRY_RUN="${NOTIFY_DRY_RUN:-0}"

webhook_url() {
  # 将来の移行のために NOTIFY_WEBHOOK_URL を優先、無ければ既存互換
  echo "${NOTIFY_WEBHOOK_URL:-${DISCORD_WEBHOOK_URL:-}}"
}

mask_url() {
  # マスク（host以降は伏せる）
  echo "$1" | sed 's#https\?://[^/]\+#https://***#'
}

json_escape() {
  # 超ミニマムなエスケープ（" と \ と改行）
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  echo "$s"
}

notify() {
  local msg="$1"
  local url
  url="$(webhook_url)"

  if [ -z "${url}" ]; then
    echo "[monitor] webhook url empty; skip notify"
    return 0
  fi

  if [ "${NOTIFY_DRY_RUN}" = "1" ]; then
    echo "[monitor] notify(dry-run): ${msg}"
    return 0
  fi

  msg="$(json_escape "$msg")"
  curl -fsS -H 'Content-Type: application/json' \
    -d "{\"content\":\"${msg}\"}" \
    "$url" >/dev/null || echo "[monitor] notify failed: url=$(mask_url "$url")"
}
