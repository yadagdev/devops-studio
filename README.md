# DevOps-Studio (devops-studio)

AlmaLinux 上で動かす「リバースプロキシ標準テンプレ」Repositoryです。  
アプリは external network `devops-edge` に参加し、Nginx から service 名でルーティングします。

## 構成

- Nginx reverse proxy: `devops-proxy`（公開: `:8081`）
- external Docker network: `devops-edge`
- 例: delay-api（別リポ）を `http://localhost:8081/delay-api/` で公開

## ディレクトリ構造
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
html/ （静的配信用）
```
## 起動方法（Almalinux 上）

```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml up -d
docker compose -f docker-compose.proxy.yaml ps
```

## 疎通確認
```
curl -i http://localhost:8081/healthz
curl -i http://localhost:8081/delay-api/healthz
```

## ルーティング追加方法（新しいアプリを増やす）
 1. アプリ側（別リポ）の docker-compose でやること
    - devops-edge に参加（external network）
    - アプリは host publish しない（expose でOK）
    - service 名で名前解決できるようにする（例: my-api）
      例:
    ```
    services:
      my-api:
      expose:
        - "3201"
      networks:
        - devops-edge

    networks:
      devops-edge:
      external: true
      name: devops-edge
    ```

 2. このRepository（devops-studio）側でやること
     - docker/proxy/nginx/conf.d/apps/my-api.conf を追加。
      template:
     ```
     location /my-api/ {
      include /etc/nginx/snippets/proxy_headers.conf;
      include /etc/nginx/snippets/proxy_common.conf;

      proxy_pass http://my-api:3201/;
     }
     ```

      反映
      ```
      cd devops-studio/docker/proxy
      docker compose -f docker-compose.proxy.yaml restart devops-proxy
      docker compose -f docker-compose.proxy.yaml exec devops-proxy nginx -t
      ```

## トラブルシュート
 Nginx が動いてるか
 ```
 cd docker/proxy
 docker compose -f docker-compose.proxy.yaml ps
 docker compose -f docker-compose.proxy.yaml logs --tail=200 devops-proxy
 ```

 コンテナ内の設定を確認
 ```
 docker exec devops-proxy nginx -T | head -n 120
 docker exec devops-proxy ls -la /etc/nginx/conf.d
 ```

### よくある原因
 - conf.d/*.conf が空（server が無い） → listen できず接続リセットになる
 - apps/*.conf に server ブロックを書いてしまう（apps は location のみ）
 - compose 実行ディレクトリを間違えて別の mount を見ている

 ## Runbook（最低限）

### proxy の状態
```
cd docker/proxy
docker compose -f docker-compose.proxy.yaml ps
docker compose -f docker-compose.proxy.yaml logs --tail=200 devops-proxy
```

### delay-api の状態（AlmaLinux）
```
cd /home/chronos/workspace/apps/delay-api
docker compose ps
docker compose logs --tail=200 delay-api
```

### 疎通
```
curl -i http://localhost:8081/healthz
curl -i http://localhost:8081/delay-api/healthz
```

## ルーティング規約（Path-based）

- 公開パスは `/<app-name>/`（末尾スラッシュあり）
- `<app-name>` は原則 **リポジトリ名 = compose service名** に合わせる
  - 例: repo `delay-api` → service `delay-api` → path `/delay-api/`
- 各アプリは `/healthz` を提供する（Nginx 経由では `/<app-name>/healthz`）
- アプリは `devops-edge` に参加し、host publish はしない（`expose` のみ）

### nginx location テンプレ
```nginx
location /<app-name>/ {
  include /etc/nginx/snippets/proxy_headers.conf;
  # include /etc/nginx/snippets/proxy_common.conf;

  proxy_pass http://<app-name>:<port>/;
}
```

## Monitoring（最小）

devops-monitor が 60秒おきに proxy 経由のエンドポイントを外形監視し、障害/復旧を Discord に通知します。

### セットアップ（Chronos）
1. `docker/monitor/monitor.env` を作成（※Git管理しない）
   - `monitor.env.sample` をコピーして Webhook URL を設定する
2. 起動：
```
cd docker/monitor
docker compose -f docker-compose.monitor.yaml up -d --build
```

3. ログ確認
```
cd docker/monitor
docker compose -f docker-compose.monitor.yaml logs -f --tail=100 devops-monitor
```

4. 障害テスト（通知確認）
 - proxy を止める：
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml stop devops-proxy
```
 - proxy を戻す：
```
cd devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml up -d devops-proxy
```

5. 監視対象の追加
`docker/monitor/app/healthcheck.sh` の `CHECK_PATHS` にパスを追加する。
 - 例: `"/new-app/healthz"
```devops-studio/docker/monitor/app/healthcheck.sh
CHECK_PATHS=(
  "/healthz"
  "/delay-api/healthz"
  "new-app/healthz"
)
```


---

6.  もし通知が来ないときに見るポイント（最短チェック）
通知が来ない原因はほぼこの3つ：

1) `monitor.env` が読み込めてない（Webhook URL 空）
2) monitor が `devops-edge` に参加してない（proxy を名前解決できない）
3) `BASE` が間違い（`http://devops-proxy` じゃなくなってる等）

  確認コマンド：
```
cd docker/monitor
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor sh -lc 'echo "$DISCORD_WEBHOOK_URL" | wc -c'
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor sh -lc 'getent hosts devops-proxy || true'
docker compose -f docker-compose.monitor.yaml exec -T devops-monitor sh -lc 'curl -i http://devops-proxy/healthz || true'
```

7. 監視間隔
- 監視間隔は `docker/monitor/monitor.env` の `INTERVAL`（秒）で調整