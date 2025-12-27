# 変更ゲート: docker/monitor（内部監視 devops-monitor）

対象:
- devops-studio リポ内 `docker/monitor/` 配下
  - docker-compose.monitor.yaml
  - app/monitor.sh, notify.sh, check_*.sh 等
- 監視対象の追加/削除、通知フォーマット、状態遷移（/state/*.state）

目的:
- 監視が「静かに壊れる」事故を防ぐ。
- 失敗/復旧の通知が正しく出ることを担保する。

---

## 0. 原則
- /host, /backups, /letsencrypt のマウントは read-only を維持。
- rate limit により 429 が出ても “監視対象が落ちてる” とは限らない。（判定条件に注意）

---

## 1. 変更前スナップショット（Chronos）
（logsにメモでOK）
```bash
cd devops-studio/

docker compose -f docker/monitor/docker-compose.monitor.yaml ps
docker compose -f docker/monitor/docker-compose.monitor.yaml logs --tail=200 devops-monitor || true

# state（状態遷移の記録）
ls -la docker/monitor/state 2>/dev/null || true
```

---

## 2. 変更反映（Chronos）
```
cd devops-studio/
git pull --ff-only
```

---

## 3. 構文・起動確認（必須）
```
# compose構文チェック（compose v2ならOK）
docker compose -f docker/monitor/docker-compose.monitor.yaml config >/dev/null

# 再起動（変更がある前提）
docker compose -f docker/monitor/docker-compose.monitor.yaml up -d --build

docker compose -f docker/monitor/docker-compose.monitor.yaml ps
```

---

## 4. 動作確認（必須）
### 4.1 “成功して静か” を確認（失敗してないこと）
```
docker compose -f docker/monitor/docker-compose.monitor.yaml logs --tail=200 devops-monitor
```

### 4.2 監視対象のHTTPチェックが実施されていること
（ログに health / upstream の成功/失敗が出る実装前提）
- [ ] /_internal/healthz をチェックしている
- [ ] /_internal/upstream/delay-api をチェックしている

---

## 5. 通知確認（推奨）
本番Webhookに影響を出したくない場合は、検証用Webhookに差し替えて短時間だけ試す。

手順例:
- monitor.env の NOTIFY_WEBHOOK_URL を検証用に変更。
- devops-monitor を再起動。
- 失敗→復旧が通知されることを確認。
- monitor.env を本番に戻す。

---

## 6. ロールバック（最低限
### 6.1 Gitで revert（推奨）
Windowsで revert→push、Chronosでpullして反映。

### 6.2 Chronosで反映＆再起動
```
cd devops-studio/
git pull --ff-only

docker compose -f docker/monitor/docker-compose.monitor.yaml up -d --build
docker compose -f docker/monitor/docker-compose.monitor.yaml ps
docker compose -f docker/monitor/docker-compose.monitor.yaml logs --tail=200 devops-monitor
```
