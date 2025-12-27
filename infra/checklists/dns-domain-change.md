# 変更ゲート: DNS / domain（ドメイン移行・到達性・証明書）

対象:
- ドメイン名の変更（duckdns → 独自ドメイン等）
- DNS A/AAAA レコード、CNAME、TTL
- certbot 対象ドメインの変更（/etc/letsencrypt）
- nginx server_name / リダイレクト / HSTS
- UptimeRobot / external-smoke の監視対象URL変更

目的:
- 移行時の “到達不能” と “証明書不整合” を防ぐ。
- 旧ドメインと新ドメインの切り替えを安全に行う。

---

## 0. 原則
- TTLを下げてから切り替える。（可能なら）
- A/AAAA を変えるなら、IPv4/IPv6両方の到達性を意識する。
- 変更は段階的に：DNS → cert → nginx → 監視
- HSTSを強くしていると移行時に戻しづらい。（今は max-age=86400 で扱いやすい）

---

## 1. 変更前スナップショット（Windows）
- [ ] 現在のドメインとDNSレコード（A/AAAA/TTL）を控える
- [ ] UptimeRobot の監視URL一覧を控える
- [ ] external-smoke の TARGET_HOST を控える
- [ ] certbot の対象ドメイン（現行）を控える

---

## 2. DNS準備（推奨）
- [ ] 可能なら TTL を短くする（移行前日〜数時間前）
- [ ] 新ドメインに A/AAAA を追加（同一IPへ）

---

## 3. Chronos 側確認（変更時に必須）
### 3.1 公開IP（IPv4/IPv6）の確認
```
ip -4 addr show dev enp5s0 | grep -E 'inet '
ip -6 addr show dev enp5s0 | grep -E 'scope global'
```

### 3.2 既存証明書の一覧
```
sudo ls -la /etc/letsencrypt/live || true
sudo certbot certificates || true
```

---

## 4. certbot（新ドメインの証明書取得/更新）
（手順は環境により異なるが、成功条件は共通）
- [ ] 新ドメインで証明書が取れる
- [ ] deploy-hook が走って nginx reload まで行く
実施後の確認:
```
sudo certbot certificates | sed -n '1,120p'
sudo journalctl -t certbot-hook --since "1 hour ago" --no-pager || true
```

---

## 5. nginx 反映（必須）
- server_name に新ドメインを追加/置換。
- 必要なら旧→新へ 301 リダイレクト（段階移行なら併存）。

検証:
```
cd devops-studio/
docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t
```

ローカル疎通（SNI合わせ）:
```
# 新ドメインに変えたら NEW_DOMAIN を設定
NEW_DOMAIN="<NEW_DOMAIN>"

curl -fsS --resolve "${NEW_DOMAIN}:443:127.0.0.1" "https://${NEW_DOMAIN}/healthz"
curl -fsS --resolve "${NEW_DOMAIN}:443:127.0.0.1" "https://${NEW_DOMAIN}/_internal/healthz"
```

---

## 6. 外部回帰（必須）
- [ ] external-smoke.yml の TARGET_HOST を新ドメインへ変更 → 手動実行で Green
- [ ] UptimeRobot の監視先を新ドメインへ更新（必要なら旧も併存）
- [ ] ブラウザで新ドメインがHTTPSで開ける（証明書OK）

---

## 7. 切り替え後の後片付け（段階的）
- [ ] TTL を元に戻す（必要なら）
- [ ] 旧ドメイン監視を停止（一定期間後）
- [ ] 旧ドメインのリダイレクト方針を確定

---

## 8. ロールバック（最低限）
- DNSを旧IP/旧設定に戻す。（TTLが短いほど戻りが速い）
- nginxの server_name を旧へ戻す。（revert推奨）
- external-smoke / UptimeRobot を旧へ戻す。

Windowsで revert:
```
git log --oneline -n 10
git revert <BAD_COMMIT_SHA>
git push
```

Chronosで pull → 検証:
```
cd devops-studio/
git pull --ff-only
docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t
```
