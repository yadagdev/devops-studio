#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/host/backups/devops-studio}"
MIN_AGE_SEC="${BACKUP_MIN_AGE_SEC:-180}"          # 新しすぎるバックアップは検証しない
STALE_SEC="${BACKUP_STALE_SEC:-172800}"           # 2日以上新しいバックアップが無いならfail
DAILY_SUMMARY="${BACKUP_DAILY_SUMMARY:-0}"        # 1で日次サマリ有効（デフォルトOFF）

STATE_DIR="${STATE_DIR:-/state}"
mkdir -p "$STATE_DIR"
DAILY_FILE="${STATE_DIR}/backup_daily.last"       # UTC日付を保存（YYYY-MM-DD）

now="$(date +%s)"

human_age() {
  local sec="$1"
  if [ "$sec" -lt 60 ]; then echo "${sec}s"; return; fi
  if [ "$sec" -lt 3600 ]; then echo "$((sec/60))m"; return; fi
  if [ "$sec" -lt 86400 ]; then echo "$((sec/3600))h"; return; fi
  echo "$((sec/86400))d"
}

mtime_epoch() { stat -c %Y "$1"; }

# 最新バックアップが存在するか
newest_any="$(ls -1t "${BACKUP_DIR}"/devops-proxy-*.tar.gz 2>/dev/null | head -n 1 || true)"
if [ -z "$newest_any" ]; then
  echo "fail|backup|no_backup_found dir=${BACKUP_DIR}"
  exit 0
fi

# 最新が古すぎないか（バックアップ停止の検知）
newest_any_age="$(( now - $(mtime_epoch "$newest_any") ))"
if [ "$newest_any_age" -gt "$STALE_SEC" ]; then
  echo "fail|backup|stale latest=$(basename "$newest_any") age=$(human_age "$newest_any_age") > $(human_age "$STALE_SEC") dir=${BACKUP_DIR}"
  exit 0
fi

# MIN_AGE_SEC以上古くて、sha256があるものを選ぶ（race回避）
eligible=""
eligible_age=""
for f in $(ls -1t "${BACKUP_DIR}"/devops-proxy-*.tar.gz 2>/dev/null); do
  age="$(( now - $(mtime_epoch "$f") ))"
  [ "$age" -ge "$MIN_AGE_SEC" ] || continue
  [ -f "${f}.sha256" ] || continue
  eligible="$f"
  eligible_age="$age"
  break
done

# MIN_AGEを満たすバックアップがまだ無い場合は「skip」でOK（stale検知は上でやってる）
if [ -z "$eligible" ]; then
  echo "ok|backup|too_new_skip latest=$(basename "$newest_any") age=$(human_age "$newest_any_age") < $(human_age "$MIN_AGE_SEC") dir=${BACKUP_DIR}"
  exit 0
fi

sha_file="${eligible}.sha256"

# ---- sha256検証（sha256ファイルが絶対パスを書いててもOK）----
expected="$(awk 'NF{print $1; exit}' "$sha_file")"
actual="$(sha256sum "$eligible" | awk '{print $1}')"

if [ -z "$expected" ] || [ -z "$actual" ]; then
  echo "fail|backup|sha256_read_error file=$(basename "$eligible")"
  exit 0
fi

if [ "$expected" != "$actual" ]; then
  echo "fail|backup|sha256_mismatch file=$(basename "$eligible")"
  exit 0
fi

# サイズ
size_bytes="$(stat -c %s "$eligible" 2>/dev/null || echo "")"
size_h="$( [ -n "$size_bytes" ] && numfmt --to=iec --suffix=B "$size_bytes" 2>/dev/null || true )"
size="${size_h:-${size_bytes:-unknown}}"

# 日次サマリ（UTCで1日1回）
# dailyを出しても必ず backup 行も出す
if [ "$DAILY_SUMMARY" = "1" ]; then
  today="$(date -u +%F)"
  last="$(cat "$DAILY_FILE" 2>/dev/null || true)"
  if [ "$today" != "$last" ]; then
    echo "$today" > "$DAILY_FILE"
    echo "ok|backup_daily|latest=$(basename "$eligible") age=$(human_age "$eligible_age") size=${size} dir=${BACKUP_DIR}"
  fi
fi

echo "ok|backup|latest=$(basename "$eligible") age=$(human_age "$eligible_age") size=${size} dir=${BACKUP_DIR}"
exit 0
