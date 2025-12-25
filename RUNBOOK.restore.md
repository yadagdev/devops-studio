devops-proxy（nginx + certbot運用資産）の復旧手順。

## 1) リポジトリ配置
```
mkdir -p /home/chronos/workspace/AIUtilizationProject
cd /home/chronos/workspace/AIUtilizationProject
git clone <your-repo> devops-studio
```

## 2) バックアップ健全性確認（推奨）
```
LATEST="$(ls -1t /home/chronos/backups/devops-studio/devops-proxy-*.tar.gz | head -n 1)"
echo "$LATEST"
gzip -t "$LATEST"
tar -tzf "$LATEST" | head -n 50
if [ -f "${LATEST}.sha256" ]; then sha256sum -c "${LATEST}.sha256"; fi
```

## 3) 展開
```
mkdir -p /tmp/restore
tar -C /tmp/restore -xzf /path/to/devops-proxy-YYYYmmdd-HHMMSS.tar.gz
```

## 4) 復元
```
sudo rsync -a /tmp/restore/etc/letsencrypt/ /etc/letsencrypt/
sudo rsync -a /tmp/restore/etc/nginx/devops-studio.htpasswd /etc/nginx/devops-studio.htpasswd 2>/dev/null || true
rsync -a /tmp/restore/repo-nginx/nginx/ /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/proxy/nginx/
rsync -a /tmp/restore/repo-nginx/.env /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/proxy/.env 2>/dev/null || true
```

## 5) 権限付与 (最小)
```
sudo chown -R root:root /etc/letsencrypt
sudo chmod -R go-rwx /etc/letsencrypt
sudo chown root:root /etc/nginx/devops-studio.htpasswd 2>/dev/null || true
sudo chmod 0640 /etc/nginx/devops-studio.htpasswd 2>/dev/null || true
```
SELinuxで読めない症状が出た時だけ：
```
sudo restorecon -Rv /etc/letsencrypt /etc/nginx 2>/dev/null || true
```

## 6) 本番起動
```
cd /home/chronos/workspace/AIUtilizationProject/devops-studio/docker/proxy
docker compose -f docker-compose.proxy.yaml up -d
docker compose -f docker-compose.proxy.yaml exec -T devops-proxy nginx -t
```

## 7) 事後確認（サーバー完結）
```
curl -fsS https://127.0.0.1/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/healthz -H 'Host: yadag-studio.duckdns.org' -I
curl -fsS https://127.0.0.1/_internal/upstream/delay-api -H 'Host: yadag-studio.duckdns.org' -I
```
