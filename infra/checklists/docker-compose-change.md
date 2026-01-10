# 変更ゲート: docker compose（サービス定義 / ネットワーク / volume / ports）

対象:
- docker compose YAML（proxy/monitor/各アプリ）
- network（devops-edge等）の接続変更
- ports/expose、volume mount、env_file、restart policy
- build/image タグ、healthcheck、depends_on

目的:
- 変更後に「コンテナは起動してるのに機能しない」事故を防ぐ。
- ports公開事故やネットワーク断（upstream解決不能）を防ぐ。

---

## 0. 原則
- “compose config が通る” は最低条件。必ず通す。
- 外部公開系（proxy）は `nginx -t` と `--resolve curl` までやる。
- ネットワーク変更は upstream name 解決（DNS）に直撃するので最重要。

---

## 1. 変更前スナップショット（Chronos / 変更前）
対象composeを `<COMPOSE>` として控える。

例:
- proxy: devops-studio/docker/proxy/docker-compose.proxy.yaml
- monitor: devops-studio/docker/monitor/docker-compose.monitor.yaml

```bash
COMPOSE="<COMPOSE>"

docker compose -f "${COMPOSE}" ps
docker compose -f "${COMPOSE}" logs --tail=200 || true
docker network ls | head -n 50
```

---

## 2. 変更反映（Chronos）
```
cd devops-studio/
git pull --ff-only
```

---

## 3. 静的検証（必須）
### 3.1 composeの構文と展開結果を確認
```
docker compose -f "${COMPOSE}" config >/dev/null
```

### 3.2 差分の危険ポイントを目視チェック（推奨）
- ports（80/443/管理ポートなど）
- network（devops-edge 参加有無）
- volume（/etc/letsencrypt, /backups, /hostなどのread-only維持）
- env_file（Git管理しないファイル参照が増えてないか）

---

## 4. 反映（必須）
### 4.1 起動/更新（buildが絡むなら --build）
```
docker compose -f "${COMPOSE}" up -d --build
docker compose -f "${COMPOSE}" ps
```

---

## 5. 動作検証（必須）
### 5-A) proxy（nginx）を含む場合
```
cd devops-studio

# nginx構文
docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t

# ローカル疎通（SNIを合わせる）
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/healthz
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/_internal/healthz
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/_internal/upstream/delay-api
```

deny_sensitive（404回帰）:
```
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/.env)" = "404"
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/.git/config)" = "404"
```

### 5-B) monitor（devops-monitor）を含む場合
```
cd devops-studio

docker compose -f docker/monitor/docker-compose.monitor.yaml ps
docker compose -f docker/monitor/docker-compose.monitor.yaml logs --tail=200 devops-monitor
```

---

## 6. 外部回帰（該当する場合）
- [ ] external-smoke（GitHub Actions）が Green
- [ ] UptimeRobot が落ちていない
- [ ] 内部監視 devops-monitor が FAILED を出していない

---

## 7. ロールバック（最低限）
### 7.1 Gitで revert（推奨）
Windowsで revert→push
```
git log --oneline -n 10
git revert <BAD_COMMIT_SHA>
git push
```

### 7.2 Chronosで pull → 再デプロイ
```
cd devops-studio
git pull --ff-only

docker compose -f "${COMPOSE}" up -d --build
docker compose -f "${COMPOSE}" ps
docker compose -f "${COMPOSE}" logs --tail=200 || true
```

※ 緊急回避（戻すまで止める）:
```
docker compose -f "${COMPOSE}" down
```
