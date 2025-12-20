# DevOps-Studio (devops-studio)

AlmaLinux上で動かす **リバースプロキシ標準テンプレ** Repositoryです。  
複数アプリを **Path-based routing**（`/<app-name>/`）で公開します。

アプリ群は external Docker network `devops-edge` に参加し、Nginx から **service 名で名前解決**してルーティングします。

---

## 現在の公開状態（重要）

- 公開ドメイン: `yadag-studio.duckdns.org`（DuckDNS / DDNS）
- 公開ポート: `80/tcp`, `443/tcp`
- HTTP(80): `/.well-known/acme-challenge/` 以外は **HTTPSへ301リダイレクト**
- HTTPS(443): **本体**（ルーティング / Basic認証 / apps）

---

## 構成

- Nginx reverse proxy: `devops-proxy`
  - 80/tcp, 443/tcp を listen
  - apps は `nginx/conf.d/apps/*.conf`（※ location のみ）
- external Docker network: `devops-edge`
- 例: delay-api（別リポ）を `https://yadag-studio.duckdns.org/delay-api/` で公開

---

## ディレクトリ構造（proxy）

```
docker/proxy/
docker-compose.proxy.yaml
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
curl -i http://localhost/healthz
curl -k -i https://localhost/healthz
curl -k -i https://localhost/delay-api/healthz
```

### 外部（LAN外 / インターネット経由）

```
### 外部（LAN外 / インターネット経由）
curl -i http://yadag-studio.duckdns.org/healthz
curl -k -i https://yadag-studio.duckdns.org/healthz
curl -k -i https://yadag-studio.duckdns.org/delay-api/healthz
```


---

## ルーティング追加方法（新しいアプリを増やす）

### 1) アプリ側（別リポ）の docker-compose でやること

- `devops-edge` に参加（external network）
- アプリは host publish しない（`ports:` を使わない）
- `expose` で内部ポートだけ出す
- **service 名**が Nginx の upstream 名になる（例: `my-api`）

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

### 2) devops-studio 側でやること（apps conf を追加）
  `docker/proxy/nginx/conf.d/apps/my-api.conf`を追加
  （apps配下は location だけ。server ブロックは書かない）
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

### ルーティング規約（Path-based）
- 公開パスは /<app-name>/（末尾スラッシュあり）
- <app-name> は原則 リポジトリ名 = compose service名 に合わせる
  - 例: repo delay-api → service delay-api → path /delay-api/
- 各アプリは /healthz を提供する
  - Nginx経由では /<app-name>/healthz
- アプリは devops-edge に参加し、host publish はしない（expose のみ）

### TLS（Let’s Encrypt / Certbot）
#### 証明書
- ホスト側: /etc/letsencrypt/live/yadag-studio.duckdns.org/
- proxy コンテナには /etc/letsencrypt を read-only マウントして利用

#### 方式
- webroot 方式で取得・更新（proxyを止めずに更新できる）

#### 更新確認（dry-run）
```
sudo certbot renew --dry-run
```

成功すると以下のように出ます（例）:

`Congratulations, all simulated renewals succeeded`

#### 自動更新
- AlmaLinux上 で systemd timer を有効化する（certbot renew 定期実行）
- 更新後に proxy の Nginx を reload して新証明書を反映

### Basic認証（公開前の最低限）
- HTTPS(443) 側に 全体 Basic認証 を適用
- 例外:
  - `/.well-known/acme-challenge/`（更新のため認証OFF）
  - `/healthz`（外部監視を通すため認証OFF。必要なら認証ONに変更してもOK）
  - `.htpasswd` は AlmaLinux 側で作成し、proxy compose で read-only マウント。

### Monitoring（最小）
- devops-monitor が一定間隔で proxy 経由のエンドポイントを監視し、
障害/復旧を Discord に通知（内形監視）。

#### セットアップ（AlmaLinux）
  1. `docker/monitor/monitor.env` を作成（※Git管理しない）
      - `monitor.env.sample` をコピーして Webhook URL などを設定

  2. 起動
      ```
      cd docker/monitor
      docker compose -f docker-compose.monitor.yaml up -d --build
      ```

  3. ログ確認
      ```
      cd docker/monitor
      docker compose -f docker-compose.monitor.yaml logs -f --tail=100 devops-monitor
      ```

#### 障害テスト（通知確認）
- proxy を止める
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml stop devops-proxy
```
- proxy を戻す
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml up -d devops-proxy
```
### 監視対象の追加
`docker/monitor/app/healthcheck.sh` の CHECK_PATHS に追加します。

例:
```
CHECK_PATHS=(
  "/healthz"
  "/delay-api/healthz"
  "/new-app/healthz"
)
```

### 監視間隔
- 監視間隔は docker/monitor/monitor.env の INTERVAL（秒）で調整。
- 外部監視（UptimeRobot）
  - 「外から到達できるか」を監視するために、外形監視を1つ入れると切り分けが速くなる。
  - https://yadag-studio.duckdns.org/healthz を HTTPS 監視

### トラブルシュート
- Nginx が動いてるか
```
cd docker/proxy
docker compose -f docker-compose.proxy.yaml ps
docker compose -f docker-compose.proxy.yaml logs --tail=200 devops-proxy
```

- コンテナ内の設定を確認
```
cd docker/proxy
docker compose -f docker-compose.proxy.yaml exec -T devops-proxy nginx -T | head -n 160
docker compose -f docker-compose.proxy.yaml exec -T devops-proxy ls -la /etc/nginx/conf.d
```

#### よくある原因

conf.d/*.conf が空（server が無い） → listen できず接続できない

apps/*.conf に server ブロックを書いてしまう（apps は location のみ）

compose 実行ディレクトリを間違えて別の mount を見ている

upstream 名の typo（例: delay-apiX） → nginx 起動失敗 or reload失敗

### Runbook（最低限）
- proxy の状態
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml ps
docker compose -f docker-compose.proxy.yaml logs --tail=200 devops-proxy
```

- delay-api の状態（例）
```
cd /home/chronos/workspace/apps/delay-api
docker compose ps
docker compose logs --tail=200 delay-api
```

- 疎通（HTTPS推奨）
```
curl -k -i https://localhost/healthz
curl -k -i https://localhost/delay-api/healthz
```