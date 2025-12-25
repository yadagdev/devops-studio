#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/host/backups/devops-studio}"
MIN_AGE_SEC="${BACKUP_MIN_AGE_SEC:-180}"          # 新しすぎるバックアップは検証しない
STALE_SEC="${BACKUP_STALE_SEC:-172800}"           # 2日以上新しいバックアップが無いならfail
DAILY_SUMMARY="${BACKUP_DAILY_SUMMARY:-1}"        # 1で日次サマリ有効

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

# 最新が古すぎないか（作られてない/止まってる検知）
newest_any_age="$(( now - $(mtime_epoch "$newest_any") ))"
if [ "$newest_any_age" -gt "$STALE_SEC" ]; then
  echo "fail|backup|stale latest=$(basename "$newest_any") age=$(human_age "$newest_any_age") > $(human_age "$STALE_SEC") dir=${BACKUP_DIR}"
  exit 0
fi

# レース回避：MIN_AGE_SEC以上古い「候補」を探す（sha256の有無は後で判定）
eligible=""
eligible_age=""
for f in $(ls -1t "${BACKUP_DIR}"/devops-proxy-*.tar.gz 2>/dev/null); do
  age="$(( now - $(mtime_epoch "$f") ))"
  [ "$age" -ge "$MIN_AGE_SEC" ] || continue
  eligible="$f"
  eligible_age="$age"
  break
done

# MIN_AGEを満たすものがまだ無い＝作成直後の窓
if [ -z "$eligible" ]; then
  echo "ok|backup|too_new_skip latest=$(basename "$newest_any") age=$(human_age "$newest_any_age") < $(human_age "$MIN_AGE_SEC") dir=${BACKUP_DIR}"
  exit 0
fi

sha_file="${eligible}.sha256"
if [ ! -f "$sha_file" ]; then
  echo "fail|backup|sha256_missing file=$(basename "$eligible") dir=${BACKUP_DIR}"
  exit 0
fi

# ---- sha256検証（絶対パスに依存しない） ----
# .sha256 は「hash  /abs/path/to/file」になってることがあるので、hashだけ抜く
base="$(basename "$eligible")"
expected="$(
  awk -v b="$base" '
    NF>=1 {
      # 行全体にbasenameが含まれる行があればそれを優先
      if (index($0, b) > 0) { print $1; exit }
    }
    END { }
  ' "$sha_file"
)"

# 見つからなければ先頭行の1カラム目にフォールバック
if [ -z "$expected" ]; then
  expected="$(awk 'NF>=1{print $1; exit}' "$sha_file")"
fi

actual="$(sha256sum "$eligible" | awk '{print $1}')"

if [ -z "$expected" ] || [ -z "$actual"]()
