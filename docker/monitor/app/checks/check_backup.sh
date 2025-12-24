#!/usr/bin/env bash
set -euo pipefail

dir="${BACKUP_DIR:-/backups}"
max_age="${BACKUP_MAX_AGE_SEC:-93600}"

latest_tgz="$(ls -1t "${dir}"/*.tar.gz 2>/dev/null | head -n 1 || true)"
if [ -z "$latest_tgz" ]; then
  echo "fail|backup|no_backup_found dir=${dir}"
  exit 0
fi

latest_sha="${latest_tgz}.sha256"
if [ ! -f "$latest_sha" ]; then
  echo "fail|backup|sha256_missing file=$(basename "$latest_tgz")"
  exit 0
fi

now_ts="$(date +%s)"
mt_ts="$(date -r "$latest_tgz" +%s)"
age=$(( now_ts - mt_ts ))

if [ "$age" -gt "$max_age" ]; then
  echo "fail|backup|backup_too_old age_sec=${age} file=$(basename "$latest_tgz")"
  exit 0
fi

# sha256 check (カレントが必要なのでdir移動)
( cd "$dir" && sha256sum -c "$(basename "$latest_sha")" >/dev/null 2>&1 ) \
  && echo "ok|backup|backup_ok file=$(basename "$latest_tgz") age_sec=${age}" \
  || echo "fail|backup|sha256_mismatch file=$(basename "$latest_tgz")"
