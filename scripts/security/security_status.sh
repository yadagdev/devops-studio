#!/usr/bin/env bash
set -euo pipefail

echo "== date =="
date
echo

echo "== firewalld =="
systemctl is-enabled firewalld 2>/dev/null || true
systemctl is-active firewalld 2>/dev/null || true
firewall-cmd --get-active-zones || true
echo "-- public zone --"
firewall-cmd --zone=public --list-all || true
echo

echo "== fail2ban =="
systemctl is-enabled fail2ban 2>/dev/null || true
systemctl is-active fail2ban 2>/dev/null || true
fail2ban-client status 2>/dev/null || true
echo "-- sshd jail --"
fail2ban-client status sshd 2>/dev/null || true
echo

echo "== dnf-automatic =="
systemctl is-enabled dnf-automatic.timer 2>/dev/null || true
systemctl is-active dnf-automatic.timer 2>/dev/null || true
systemctl status dnf-automatic.timer --no-pager 2>/dev/null | sed -n '1,120p' || true
echo

echo "== nginx/proxy sanity (local) =="
# Hostヘッダ付きでlocalhost疎通（証明書/TLS経路は proxy 側が稼働していればOK）
curl -fsS https://127.0.0.1/healthz -H 'Host: yadag-studio.duckdns.org' -I 2>/dev/null || true
curl -fsS https://127.0.0.1/_internal/healthz -H 'Host: yadag-studio.duckdns.org' -I 2>/dev/null || true
echo
