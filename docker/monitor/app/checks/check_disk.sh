#!/usr/bin/env bash
set -euo pipefail

# env:
# DISK_PATH, DISK_USE_PCT_MAX
path="${DISK_PATH:-/host}"
max="${DISK_USE_PCT_MAX:-85}"

# POSIXっぽく -P を使う
use_pct="$(df -P "$path" | awk 'NR==2{gsub("%","",$5); print $5}')"
if [ -z "$use_pct" ]; then
  echo "fail|disk|cannot_read_df"
  exit 0
fi

if [ "$use_pct" -ge "$max" ]; then
  echo "fail|disk|disk_usage=${use_pct}% >= ${max}% path=${path}"
else
  echo "ok|disk|disk_usage=${use_pct}% path=${path}"
fi
