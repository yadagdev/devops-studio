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
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor \
  env NOTIFY_DRY_RUN=1 /app/checks/check_backup.sh
```