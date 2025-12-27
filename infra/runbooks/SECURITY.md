Chronos（AlmaLinux）+ devops-proxy（nginx）まわりのセキュリティ運用を“短く”固定化する。

## 0) 方針（短い版）
- 外部露出は 80/443 のみ（ルータも同様）
- SSH(22) は LAN限定（firewalldのrich rule + fail2ban）
- /_internal/* のみ保護（Basic認証）
- “漏れたら困る物”は nginx で 404（deny_sensitive）
- TLSは 1.2/1.3 中心 + HSTS は短め（86400）

---

## 1) 日常チェック（スクリプト実行）
```
sudo /home/chronos/workspace/AIUtilizationProject/devops-studio/scripts/security/security_status.sh
```

## 2) firewalld（確認だけ）
```
sudo firewall-cmd --get-active-zones
sudo firewall-cmd --zone=public --list-all
sudo firewall-cmd --list-rich-rules --zone=public
```
### よくある事故
- sshを誤って全開放しない（LANのみ許可になっていること）
- 8081/8443 など検証ポートを public に許可しない（ローカルbindで十分）

## 3) fail2ban（確認だけ）
```
sudo fail2ban-client status
sudo fail2ban-client status sshd
sudo journalctl -u fail2ban --since "7 days ago" --no-pager | tail -n 200
```

## 4) dnf-automatic（確認だけ）
```
sudo systemctl status dnf-automatic.timer --no-pager
sudo journalctl -u dnf-automatic --since "14 days ago" --no-pager | tail -n 200
```

## 5) nginx（守ってる理由）
- deny_sensitive：.env や .git、鍵/証明書などを 404 にして“取りこぼし”を潰す
- rate-limit(health)：スキャン/過負荷の踏み台にならないように“軽く”制限する（429は正常）
- TLS 1.2/1.3：古い暗号スイートを落として“攻撃面”を狭くする
- HSTS(86400)：HTTPS固定を促すが、失敗時の復旧も困らないよう短めにする

## 6) 最低限の自己点検（サーバー完結）
```
curl -fsS https://127.0.0.1/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/healthz -H 'Host: yadag-studio.duckdns.org' -I

# TLS (1.2 OK / 1.1 NG など)
openssl s_client -connect 127.0.0.1:443 -servername yadag-studio.duckdns.org -tls1_2 </dev/null 2>/dev/null | head -n 30 || true
```

## 7) 変更時チェックリスト（事故防止）
- nginx設定を変えた：nginx -t → curl localhost → OKなら reload
- cert周り触った：certbot renew --dry-run は触れる時だけ、基本は timer に任せる
- firewalld触った：sshがLAN限定のままか確認
