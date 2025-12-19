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