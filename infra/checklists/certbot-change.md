# 変更ゲート: certbot renew / deploy-hook / nginx reload

対象:
- certbot renew の運用（systemd timer 等）
- deploy-hook（例: /usr/local/bin/reload-devops-proxy.sh）
- 証明書の更新と nginx reload の結線

目的:
- 証明書更新の失敗・更新後未反映（reload漏れ）を防ぐ。

---

## 1. 変更前セルフチェック（Windows）
- [ ] 変更点が “hook/タイマー/パス/compose指定” のどれか把握できている
- [ ] secrets（ACME設定等）をコミットしない
- [ ] ロールバック可能（前コミットへ戻せる）

---

## 2. Chronos 側の事前確認（変更前）
```
systemctl list-timers --all | grep -E 'certbot|renew' || true
sudo journalctl -u certbot-renew.service --since "7 days ago" --no-pager || true
```

（ユニット名は環境により異なるので、実名に合わせる）

---

## 3. hook の健全性確認（必須）
対象例:
- /usr/local/bin/reload-devops-proxy.sh

確認:
```
sudo bash -n /usr/local/bin/reload-devops-proxy.sh
```

手動dry-run（可能なら）:
- certbot 側の dry-run は ACME の制限に注意しつつ実施。

```
sudo certbot renew --dry-run
```

---

## 4. nginx 側の反映確認（必須）
```
docker compose -f /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t
```

---

## 5. 更新後検証（証明書期限）
```
sudo openssl x509 -in /etc/letsencrypt/live/yadag-studio.duckdns.org/fullchain.pem -noout -dates
```

---

## 6. 監視
- [ ] UptimeRobot 継続OK
- [ ] devops-monitor の cert check が OK / 期限が十分残っている
- [ ] certbot-hook の logger が journal に出ている（deploy-hook実行の証跡）

---

## 7. ロールバック（最低限）
- hook の変更を戻す。
- nginx reload ルートが死んでいないこと（nginx -t が通る）を確認。
