# 変更ゲート: nginx（devops-proxy）設定変更

対象:
- devops-studio の nginx 設定（conf.d / snippets / includes / deny_sensitive / ratelimit 等）
- certbot deploy-hook / reload スクリプトの変更もここに準拠

目的:
- 外部公開に直結する変更を「事故らず」「再現性高く」反映する。

---

## 0. 事前条件
- 変更は GitHub に push 済み。
- Chronos では pull + 検証コマンドのみ。（原則）
- ヘルス系は rate limit により 429 が出ても正常扱い。（過負荷時）

---

## 1. 変更前セルフチェック（Windows）
- [ ] `git diff` で意図しない差分がない。
- [ ] secrets/個人情報が混入していない。（`.env` / token / webhook / 鍵）
- [ ] 変更対象ファイルの一覧をメモできる。（レビュー用）
- [ ] ロールバックが可能。（前コミットに戻せる）

---

## 2. Chronos反映（Chronos: AlmaLinux10.1）
### 2.1 pull
```
cd devops-studio
git pull --ff-only
```

### 2.2 nginx 構文チェック（必須）
```
cd devops-studio/
docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t
```

期待結果:
- syntax is ok
- test is successful

NGなら:
- 変更を戻す（ロールバック）か、修正コミットを作る。

---

## 3. ローカル疎通（Chronosからの確認）
※ https://127.0.0.1 直叩きは証明書検証で落ちるので --resolve を使う。
```
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/healthz
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/_internal/healthz
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/_internal/upstream/delay-api
```

deny_sensitive 回帰（404になること）:
```
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/.env)" = "404"
test "$(curl -s -o /dev/null -w '%{http_code}' --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/.git/config)" = "404"
```

---

## 4. 外部到達（external-smoke）
- [ ] .github/workflows/external-smoke.yml を手動実行して Green を確認
- [ ] 以後は cron で定期実行される（ただし多少遅延することがある）

---

## 5. 反映確認（監視）
- [ ] UptimeRobot（外形監視）が落ちていない
- [ ] 内部監視 devops-monitor が FAILED を出していない
- [ ] もしFAILEDが出たら、直前の変更を疑う（ロールバック検討）

---

## 6. ロールバック（最低限）
前コミットに戻して反映（Windowsで revert 推奨）:
- [ ] revertコミットを作成して push
- [ ] Chronos で pull
- [ ] nginx -t と --resolve curl を再実行

### Windows（revertコミットを作る）
1) 直前の変更コミットを revert（コミットIDは状況に応じて指定）
```
git log --oneline -n 10
git revert <BAD_COMMIT_SHA>
git push
```

※複数コミットを戻すなら範囲指定も可:
```
git revert <OLD_SHA>.. <NEW_SHA>
git push
```

### Chronos（pullして検証）
```
cd devops-studio
git pull --ff-only

docker compose -f docker/proxy/docker-compose.proxy.yaml exec -T devops-proxy nginx -t

curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/healthz
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/_internal/healthz
curl -fsS --resolve ops.yadag.fyi:443:127.0.0.1 https://ops.yadag.fyi/_internal/upstream/delay-api
```