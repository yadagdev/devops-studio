#!/usr/bin/env bash
set -euo pipefail

cert="${CERT_FULLCHAIN:-}"
min_days="${CERT_DAYS_MIN:-14}"

if [ -z "$cert" ] || [ ! -f "$cert" ]; then
  echo "fail|cert|cert_not_found path=${cert}"
  exit 0
fi

enddate="$(openssl x509 -enddate -noout -in "$cert" | cut -d= -f2)"
end_ts="$(date -d "$enddate" +%s)"
now_ts="$(date +%s)"
remain_sec=$(( end_ts - now_ts ))
remain_days=$(( remain_sec / 86400 ))

if [ "$remain_days" -le "$min_days" ]; then
  echo "fail|cert|cert_expires_in=${remain_days}d (<=${min_days}d) end=${enddate}"
else
  echo "ok|cert|cert_expires_in=${remain_days}d end=${enddate}"
fi
