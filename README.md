# DevOps-Studio (devops-studio)

DevOps-Studio は、**自宅マルチマシン + GitHub + ローカルLLM** を前提にした「個人開発向けの統合DevOps基盤」です。

このリポジトリはその中でも主に **AlmaLinux)上での公開基盤（nginx reverse proxy + 運用）** を提供します。

---

## 重要：現在の公開状態

- 公開ドメイン: `yadag-studio.duckdns.org`（DuckDNS / DDNS）
- 公開ポート: `80/tcp`, `443/tcp`
- 80/tcp: `/.well-known/acme-challenge/` 以外は **HTTPSへ301**
- 443/tcp: **本体**（ルーティング / ルール / 内部エンドポイント / 運用保護）

---

## ざっくりとした構成（proxy）

- Nginx reverse proxy: `devops-proxy`
  - 80/443 を listen
  - 複数アプリを **Path-based routing**（`/<app-name>/`）で公開
- external Docker network: `devops-edge`
  - アプリ群は `devops-edge` に参加
  - Nginx から **service名で名前解決**して upstream する

例: `delay-api`（別リポ）を `https://yadag-studio.duckdns.org/delay-api/` で公開

---

## ドキュメント

- [Architecture](infra/ARCHITECTURE.md)
- [Project Charter](infra/PROJECT_CHARTER.md)

### 運用Runbook（AlmaLinux運用の手順）
- [MONITOR](infra/runbooks/MONITOR.md)
- [BACKUP](infra/runbooks/BACKUP.md)
- [RESTORE](infra/runbooks/RESTORE.md)
- [SECURITY](infra/runbooks/SECURITY.md)

### Change Gates（変更種別ゲート / 提出前チェック）

#### Infra / Ops
- [Nginx（devops-proxy）](infra/checklists/nginx-change.md)
- [firewalld](infra/checklists/firewalld-change.md)
- [certbot / deploy-hook](infra/checklists/certbot-change.md)
- [backup（systemd timer + script）](infra/checklists/backup-change.md)
- [systemd（service/timer全般）](infra/checklists/systemd-change.md)
- [docker compose（全般）](infra/checklists/docker-compose-change.md)
- [security headers / deny_sensitive](infra/checklists/security-headers-change.md)

#### Observability / CI
- [internal monitor（docker/monitor）](infra/checklists/monitor-change.md)
- [GitHub Actions / self-hosted runner](infra/checklists/github-actions-runner-change.md)

#### Domain
- [DNS / domain](infra/checklists/dns-domain-change.md)

---

## ディレクトリ構造（proxy）

```
docker/proxy/
docker-compose.proxy.yaml
docker-compose.proxy.rehearsal.override.yaml
nginx/
conf.d/
00_base.conf
apps/
00_placeholder.conf
delay-api.conf
snippets/
proxy_headers.conf
proxy_common.conf
html/ # 静的配信用（任意）
```

## 起動方法（AlmaLinux）

```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml up -d
docker compose -f docker-compose.proxy.yaml ps
```

## 疎通確認

### ローカル（AlmaLinux）

```
curl -fsS https://127.0.0.1/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/upstream/delay-api -H 'Host: yadag-studio.duckdns.org' -I
```

### 外部（LAN外 / インターネット経由）

```
curl -fsS https://yadag-studio.duckdns.org/healthz -I
curl -fsS https://yadag-studio.duckdns.org/_internal/healthz -I
curl -fsS https://yadag-studio.duckdns.org/_internal/upstream/delay-api -I
```

---

## ルーティング追加方法（新しいアプリを増やす）

### 1) アプリ側（別リポ）の docker-compose でやること
- `devops-edge` に参加（external network）
- アプリは host publish しない（`ports:` を使わない）
- `expose` で内部ポートだけ出す
- service 名が Nginx の upstream 名になる（例: `my-api`）

例:

```
services:
  my-api:
    image: my-api:latest
    expose:
      - "3201"
    networks:
      - devops-edge

networks:
  devops-edge:
    external: true
    name: devops-edge
```

### 2) devops-studio 側（apps conf を追加）
  `docker/proxy/nginx/conf.d/apps/my-api.conf`を追加
  （apps配下は location のみで server ブロックは書かない）
  テンプレ:
  ```
  location /my-api/ {
    include /etc/nginx/snippets/proxy_headers.conf;
    include /etc/nginx/snippets/proxy_common.conf;

    proxy_pass http://my-api:3201/;
  }
  ```
  反映:
  ```
  cd devops-studio/docker/proxy
  docker compose -f docker-compose.proxy.yaml exec -T devops-proxy nginx -t
  docker compose -f docker-compose.proxy.yaml exec -T devops-proxy nginx -s reload
  ```

## TLS（Let’s Encrypt / Certbot）
- ホスト側: `/etc/letsencrypt/live/yadag-studio.duckdns.org/`
- proxy コンテナへ `/etc/letsencrypt` を read-only マウントして利用
- certbot renew は systemd timer で定期実行
- renew後に deploy-hook で nginx reload
（必要なときだけ）dry-run:
  ```
  sudo certbot renew --dry-run
  ```

## Basic認証
- 公開アプリは原則かけない
- `/_internal/*` や管理系のみ保護する
- 監視（UptimeRobot/内部監視）は認証なしで叩けるエンドポイントを使う

## Monitoring（通知は異常/復旧のみ）
- 外形監視: UptimeRobot
- 内形監視: `docker/monitor` の `devops-monitor` コンテナ
   - `monitor.sh` が本体（state管理 + 通知制御）
   - `monitor.env` は Git 管理しない（sampleあり）

セットアップ:
```
cd devops-studio/docker/monitor
cp monitor.env.sample monitor.env
# monitor.env を編集して NOTIFY_WEBHOOK_URL などを設定
docker compose -f docker-compose.monitor.yaml up -d --build
```

ログ確認:
```
cd devops-studio/docker/monitor
docker compose -f docker-compose.monitor.yaml logs -f --tail=200 devops-monitor
```

## Backup / Restore / Security / Monitoring（運用手順はRunbookへ）
- [MONITOR](infra/runbooks/MONITOR.md)
- [BACKUP](infra/runbooks/BACKUP.md)
- [RESTORE](infra/runbooks/RESTORE.md)
- [SECURITY](infra/runbooks/SECURITY.md)

## トラブルシュート（最低限）
### proxyの状態確認
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml ps
docker compose -f docker-compose.proxy.yaml logs --tail=200 devops-proxy
```

### コンテナ内の設定確認
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml exec -T devops-proxy nginx -T | head -n 200
docker compose -f docker-compose.proxy.yaml exec -T devops-proxy ls -la /etc/nginx/conf.d
```

### よくある原因
- `apps/*.conf` に server ブロックを書いている（appsはlocationのみ）
- upstream名の typo（service名と一致しない）
- compose実行ディレクトリを間違えて mount がズレている

### ルーティング規約（Path-based）
- 公開パスは /<app-name>/（末尾スラッシュあり）
- <app-name> は原則 リポジトリ名 = compose service名 に合わせる
  - 例: repo delay-api → service delay-api → path /delay-api/
- 各アプリは /healthz を提供する
  - Nginx経由では /<app-name>/healthz
- アプリは devops-edge に参加し、host publish はしない（expose のみ）
