# 変更ゲート: deny_sensitive / security headers（nginx防御設定）

対象:
- deny_sensitive.conf（/.env, /.git/*, dotfiles, backup拡張子, key/cert 等の遮断）
- security headers（HSTS 等）
- TLS設定（TLS1.2/1.3、弱い暗号の排除など）
- health系の rate limit（limit_req/limit_conn）
- access_log 抑制、スキャン可視化設定など「公開面の防御」全般

目的:
- 意図せず “穴が開く” を防ぐ。
- 変更後も最低限のヘッダ/遮断/HTTPSが維持されることを担保する。

---

## 0. 原則
- 公開面の防御設定は「壊れても気づきにくい」が「壊れた瞬間に危ない」。
- 変更後は必ず “ローカル（Chronos）” と “外部（external-smoke/UptimeRobot）” の両方で回帰確認する。
- health系は 429 が出ることを許容。（wrk等で 429 は正常系）

---

## 1. 変更前スナップショット（Chronos / 変更前）
（Gitに入れない。logsに貼ればOK）
```
cd devops-studio/

# nginx構文が通っていること（現状確認）
docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t

# 参考: 有効設定のダンプ（量が多いので必要時のみ）
# docker compose -f ... exec -T devops-proxy nginx -T > /tmp/nginx-T.before.txt
```

---

## 2. 変更反映（Chronos）
```
cd devops-studio/
git pull --ff-only
```

---

## 3. 必須検証（Chronos）
### 3.1 nginx構文チェック（必須）
```
cd devops-studio

docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t
```

### 3.2 HTTPSローカル疎通（SNIを合わせる）
```
curl -fsS --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/healthz
curl -fsS --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/_internal/he
```

### 3.3 deny_sensitive 回帰（404/410ではなく「外に見せない」が目的 → 404が望ましい）
```
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/.env)" = "404"
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/.git/config)" = "404"
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/.ssh/id_rsa)" = "404"
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/backup.tar.gz)" = "404"
```

### 3.4 Security headers 回帰（HSTS）
```
curl -sSI --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/healthz \
  | tr -d '\r' \
  | grep -i '^strict-transport-security:' >/dev/null
```

### 3.5 TLSざっくり確認（推奨）
証明書CN/SANやハンドシェイクの雰囲気を見る（詳細解析は不要）
```
echo | openssl s_client -connect 127.0.0.1:443 -servername yadag-studio.duckdns.org 2>/dev/null | head -n 30
```

### 3.6 rate limit の確認（推奨）
短時間で複数叩いて 429 が混ざるならOK（健康系に限る）
```
for i in $(seq 1 30); do
  curl -s -o /dev/null -w '%{http_code}\n' --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/_internal/healthz
done | sort | uniq -c
```

---

## 4. 外部回帰（必須）
- [ ] external-smoke が Green（HSTS/deny_sensitive/health）
- [ ] UptimeRobot が落ちていない
- [ ] 内部監視 devops-monitor が FAILED を出していない

---

## 5. ロールバック（最低限）
### 5.1 Git revert（推奨）
Windowsで revert → push
```
git log --oneline -n 10
git revert <BAD_COMMIT_SHA>
git push
```

### 5.2 Chronos pull → nginx検証
```
cd devops-studio/
git pull --ff-only

docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t
curl -fsS --resolve yadag-studio.duckdns.org:443:127.0.0.1 https://yadag-studio.duckdns.org/healthz
```
