devops-studio 内部監視（devops-monitor）の運用手順。

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

## 無通知検証 (DRY_RUN)
`monitor.sh`は無限ループなので`timeout`を使う。
```
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor env NOTIFY_DRY_RUN=1 timeout 20s /app/monitor.sh || true
```

個別チェック：
```
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor env NOTIFY_DRY_RUN=1 /app/checks/check_backup.sh
```

## 疑似障害 (無通知推奨)
### HTTPを落とす（安全）
```
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor \
  env NOTIFY_DRY_RUN=1 BASE=http://devops-proxy-nope timeout 20s /app/monitor.sh || true
```

#### upstream(delay-api) を落として復旧も確認（コンテナ名は環境で置換）
```
docker stop delay-api
docker start delay-api
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
