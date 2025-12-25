#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/home/chronos/backups/devops-studio}"

latest="$(ls -1t "${BACKUP_DIR}"/devops-proxy-*.tar.gz 2>/dev/null | head -n 1 || true)"
if [ -z "${latest}" ]; then
  echo "[backup-verify] NG: no backup found in ${BACKUP_DIR}"
  exit 1
fi

sha="${latest}.sha256"
if [ ! -f "${sha}" ]; then
  echo "[backup-verify] NG: sha256 file missing: ${sha}"
  exit 1
fi

echo "[backup-verify] target: ${latest}"
echo "[backup-verify] mtime : $(date -d "@$(stat -c %Y "${latest}")" "+%F %T %Z")"
echo "[backup-verify] size : $(numfmt --to=iec --suffix=B "$(stat -c %s "${latest}")" 2>/dev/null || stat -c %s "${latest}")"

# gzip integrity
gzip -t "${latest}"

# tar list sanity (heavyになりすぎないよう先頭だけ)
tar -tzf "${latest}" | head -n 50 >/dev/null

# sha256 verify
sha256sum -c "${sha}"

echo "[backup-verify] OK"
