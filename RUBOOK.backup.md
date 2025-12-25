# Chronos上の devops-proxy バックアップ運用（systemd timer + /usr/local/bin/backup-devops-proxy.sh）。

## 0) 目的
- 「バックアップが回っているか」を最小コストで確認できる
- 「壊れていないか（gzip/tar/sha256）」を定型化して確認できる
- 復旧の入口（RUNBOOK.restore.md）へ迷わず繋げる

---

## 1) systemd（タイマー稼働）確認

### タイマーの状態
```
systemctl status backup-devops-proxy.timer --no-pager
systemctl list-timers --all | grep -E "backup-devops-proxy\\.timer|NEXT|LAST" -n || true
```

### 直近の実行ログ（成功/失敗の確認）
```
journalctl -u backup-devops-proxy.service --since "7 days ago" --no-pager
journalctl -u backup-devops-proxy.service --since "7 days ago" --no-pager | egrep -i "error|failed|no such|permission|tar:|sha256|gzip" || true
```

## 2) 最新バックアップの健全性確認（定型）
### 推奨コマンド
```
/home/chronos/workspace/AIUtilizationProject/devops-studio/scripts/backup/verify_latest_devops_proxy_backup.sh
```

（任意）バックアップディレクトリを変える場合：
```
BACKUP_DIR=/home/chronos/backups/devops-studio \
  /home/chronos/workspace/AIUtilizationProject/devops-studio/scripts/backup/verify_latest_devops_proxy_backup.sh
```

### 手動で確認する場合
```
LATEST="$(ls -1t /home/chronos/backups/devops-studio/devops-proxy-*.tar.gz | head -n 1)"
echo "$LATEST"
gzip -t "$LATEST"
tar -tzf "$LATEST" | head -n 50
sha256sum -c "${LATEST}.sha256"
```

## 3) 容量の確認（詰まる前に気付く）
```
df -h /
du -sh /home/chronos/backups/devops-studio
ls -lh /home/chronos/backups/devops-studio | tail -n 30
```

## 4) 復旧へ進む
復旧は以下を参照：
- [RUNBOOK.restore.md](RUNBOOK.restore.md)