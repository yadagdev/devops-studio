# devops-studio 内部監視（devops-monitor）の運用手順。

## 方針
- 通知は基本「異常」と「復旧」のみ
- 日次サマリ（backup_daily）はデフォルトOFF（必要な期間だけON）
- 無通知検証は `NOTIFY_DRY_RUN=1` を使う

## 起動
```
cd /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/monitor
docker compose -f docker-compose.monitor.yaml up -d --build
docker compose -f docker-compose.monitor.yaml ps
```

## ログ
```
docker compose -f docker-compose.monitor.yaml logs -n 200 --no-log-prefix devops-monitor
```

## state (状態遷移の根拠)
```
cd /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/monitor
ls -la state/
find state -maxdepth 1 -type f -print -exec sed -n '1,120p' {} \;
```

## 日次サマリ
- `BACKUP_DAILY_SUMMARY=1`で有効
- daily は state を触らない（状態遷移に影響しない）
```
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor \
  env NOTIFY_DRY_RUN=1 BACKUP_DAILY_SUMMARY=1 /app/checks/check_backup.sh
```

## サーバー完結の外部スキャン代替
```
curl -fsS https://127.0.0.1/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/upstream/delay-api -H 'Host: yadag-studio.duckdns.org' -I

sudo firewall-cmd --zone=public --list-all
sudo fail2ban-client status sshd
```

## 無通知検証（状態遷移の確認：FAILED / recovered）

監視は「状態遷移が起きたときだけ」通知する設計。
そのため、通常時はログも通知も静かなのが正しい。

### 1) DRY_RUNで20秒だけ回して“通知文面”をstdoutに出す
（Webhookへは送られない）

```
cd /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/monitor
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor \
  env NOTIFY_DRY_RUN=1 timeout 20s /app/monitor.sh || true
```

### 2) 擬似障害：BASEを壊して http をFAILEDにする（DRY_RUN）
```
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor \
  env NOTIFY_DRY_RUN=1 BASE=http://devops-proxy-nope timeout 20s /app/monitor.sh || true
```
期待する出力例（stdout）：
- [health] 🚨 http FAILED: ...

#### upstream(delay-api) を落として復旧も確認（コンテナ名は環境で置換）
```
docker stop delay-api
docker start delay-api
```

### 3) 正常に戻して recovered を確認（DRY_RUN）
```
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor \
  env NOTIFY_DRY_RUN=1 timeout 20s /app/monitor.sh || true
```
期待する出力例（stdout）：
- [health] ✅ http recovered: ...

## 監視が“生きている”ことの無通知確認（stateを見る）
通知が来なくても、stateファイルが更新されていれば監視ループは動いている。

### stateの最終更新時刻を見る
```
cd /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/monitor
ls -lt state/*.state state/backup_daily.last 2>/dev/null | head -n 20
```

### stateの中身（ok/fail）を一覧で見る
```
for f in state/*.state; do
  printf "%-20s %s\n" "$(basename "$f")" "$(cat "$f")"
done
```

### 監視コンテナの死活（ps/logs）
```
docker compose -f docker-compose.monitor.yaml ps
docker compose -f docker-compose.monitor.yaml logs -n 50 --no-log-prefix devops-monitor
```
