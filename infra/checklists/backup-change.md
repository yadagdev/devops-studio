# 変更ゲート: backup（systemd timer / backup-devops-proxy.sh / 世代管理）

対象:
- /usr/local/bin/backup-devops-proxy.sh
- backup-devops-proxy.service / backup-devops-proxy.timer
- バックアップ対象（nginx設定、letsencrypt、htpasswd、.env等）の変更
- 世代管理（削除条件）や検証方法（sha256, tar, gzip）

目的:
- バックアップが「成功ログだけ出て中身が壊れてる」事故を防ぐ。
- 復旧できるバックアップであることを担保する。

---

## 0. 原則
- バックアップは “作って終わり” ではなく “検証して初めて価値が出る”。
- secrets をGitに入れない。（.env 等はバックアップ対象でもGit管理しない）
- 変更後は「作成→整合性→復旧リハ」の最低ラインを通す。

---

## 1. 変更前スナップショット（Chronos / 変更前）
（Gitに入れない。logsに残せばOK）
```
# 現行ユニットの内容
systemctl cat backup-devops-proxy.service
systemctl cat backup-devops-proxy.timer

# 直近の実行ログ
sudo journalctl -u backup-devops-proxy.service --since "14 days ago" --no-pager | tail -n 200

# バックアップ保存先の一覧（最新確認）
ls -lah /home/chronos/backups/devops-studio | tail -n 50
```

---

## 2. 変更反映（Chronos）
```
cd devops-studio/
git pull --ff-only
```

---

## 3. 変更後の即時テスト（必須）
### 3.1 backupスクリプトの構文チェック
```
sudo bash -n /usr/local/bin/backup-devops-proxy.sh
```

### 3.2 systemd ユニット再読込
```
sudo systemctl daemon-reload
```

### 3.3 手動実行（timer待ちにしない）
```
sudo systemctl start backup-devops-proxy.service
sudo journalctl -u backup-devops-proxy.service --since "10 minutes ago" --no-pager
```

期待:
- tar.gz が作成される。
- sha256 が作成される。
- エラー終了していない。

---

## 4. 生成物の整合性チェック（必須）
最新のアーカイブを1つ選んで検証する（例としてLATESTを使う）:
```
LATEST="$(ls -1t /home/chronos/backups/devops-studio/devops-proxy-*.tar.gz | head -n 1)"
echo "$LATEST"

# gzipレベルの破損がないか
gzip -t "$LATEST"

# tarの一覧が取れるか
tar -tzf "$LATEST" >/dev/null

# sha256があるか・一致するか
test -f "${LATEST}.sha256"
sha256sum -c "${LATEST}.sha256"
```

---

## 5. 最低限の復旧リハ（推奨、ただし変更が大きい場合は必須）
“本番に影響しないパス” へ展開して中身を確認する:
```
WORK="/tmp/restore-rehearsal-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WORK"
tar -xzf "$LATEST" -C "$WORK"
ls -la "$WORK" | head
```
確認観点（例）:
- nginx設定ディレクトリが期待通り含まれる。
- letsencrypt が含まれる。（必要な場合）
- htpasswd / .env は「存在するなら入っている」想定通りか。

---

## 6. 世代管理（削除）変更の検証（該当する場合）
削除条件を変えた場合は、dry-run相当の確認を先にやる（例: 対象一覧を出す）。
例: “14日より古い対象” を表示する。（削除はしない）
```
find /home/chronos/backups/devops-studio -type f -name 'devops-proxy-*.tar.gz' -mtime +14 -print | head
find /home/chronos/backups/devops-studio -type f -name 'devops-proxy-*.tar.gz.sha256' -mtime +14 -print | head
```

---

## 7. ロールバック（最低限）
### 7.1 Gitで revert（推奨）
Windowsで revert → push
```
git log --oneline -n 10
git revert <BAD_COMMIT_SHA>
git push
```

### 7.2 Chronosで pull → 再テスト
```
cd devops-studio/
git pull --ff-only

sudo systemctl daemon-reload
sudo systemctl start backup-devops-proxy.service
sudo journalctl -u backup-devops-proxy.service --since "10 minutes ago" --no-pager
```
（整合性チェックも再実行）