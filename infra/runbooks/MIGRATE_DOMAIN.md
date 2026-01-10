# 目的
外部監視（UptimeRobot）で発生している 監視URLのDOWN/UPフラップを解消するために、外向けの名前解決基盤を DuckDNS → Cloudflare（yadag.fyi） に移行すること。

- 外部経路の不安定さを、内部監視（devops-proxy:18080）から切り離す。
- 障害時の切り分けを簡単にし、再発防止につなげる（DNS/経路/証明書/アプリの責務分離）。

## 現象（DNS timeout / connect timeout / 127.0.0.1 forced OK）

1) 外部向け FQDN で timeout が出る。
 `curl -4` にて、以下が断続的に発生する：
   - `Resolving timed out after 2000 milliseconds`（DNS timeout）
   - `Connection timed out after 2002 milliseconds`（connect timeout）
   - `code=000` で応答が取れない

示唆：
- nginx/アプリ以前に 名前解決 or 外部到達性が揺れている可能性がある。

2) 127.0.0.1 に強制すると常にOK
以下のように --resolve ...:443:127.0.0.1 を指定すると安定して 200 が返る：
```
curl -sSv --connect-timeout 2 --max-time 10 \
  --resolve yadag-studio.duckdns.org:443:127.0.0.1 \
  https://yadag-studio.duckdns.org/healthz -o /dev/null
```

示唆：
- nginx（ローカル）や証明書、/healthz 実装自体は正常。
- 問題は 外部DNS/外部経路（ISP、IPv6、DuckDNS、経路）側の可能性が高い。

## 対応方針
- 内部監視：devops-edge 経由で http://devops-proxy:18080 を叩く（外部DNS/外部経路に依存しない）。
- 外部監視（UptimeRobot）：Cloudflare 管理ドメイン yadag.fyi の ops.yadag.fyi を監視対象に切り替える。
- これにより「外部の揺れ」と「内部実状態」を分離し、誤検知と通知ノイズを削減する。

## 前提
- Cloudflare にて yadag.fyi を取得済み（zoneが存在する）。
- Chronos の外部公開は 80/443 を devops-proxy（nginx）コンテナが受けている。
- Let’s Encrypt（certbot）で証明書を管理し、HTTP-01（webroot）で更新できる状態。
- devops-proxy の /.well-known/acme-challenge/ は auth 無しで到達できる（80, 443両方）。

## 移行対象
- 移行先 FQDN：ops.yadag.fyi
- 監視対象URL（外部）：
  - https://ops.yadag.fyi/healthz
  - https://ops.yadag.fyi/_internal/healthz
  - https://ops.yadag.fyi/_internal/upstream/delay-api
- 内部監視BASE：http://devops-proxy:18080

## Cloudflare ダッシュボード手順（DNS / レコード / 反映確認）
### Cloudflare SSL/TLS 設定（重要）
Cloudflare → SSL/TLS → Overview の mode は以下を推奨：

- 推奨：Full (strict)
  - Cloudflare が Origin（Chronos/nginx）の証明書も検証するため安全
- 非推奨：Flexible（Origin が HTTP 扱いになり、意図せず挙動が変わる可能性あり）

### 手順A：DNSレコード作成（ops.yadag.fyi）

Cloudflare → yadag.fyi → DNS → Records → Add record
推奨（IPv4/IPv6を追加）：
- Type: A
- Name: ops
- IPv4 address: <ChronosのグローバルIPv4>（例: 218.xxx.xxx.xxx）
- Proxy status: Proxied OFF（あとでONにする。）
- TTL: Auto

---

- Type: AAAA
- Name: ops
- IPv6 address: <ChronosのグローバルIPv6>
- Proxy status: Proxied OFF（あとでONにする。）
- TTL: Auto

疎通確認と証明書の検証が終わったら：
- Proxy status: Proxied（ON）

### 手順B：反映確認（DNS）
- Cloudflare上でレコードを作ったら、Chronos から確認する：
```
dig +short ops.yadag.fyi A
# 期待：自分のグローバルIPv4が返る
dig +short ops.yadag.fyi AAAA
# 期待：自分のグローバルIPv6が返る
```
（dig が無ければ getent hosts ops.yadag.fyi でも可）

## nginx 設定変更（server_name / 証明書の移行）
1) server_name に ops.yadag.fyi を追加

server_name yadag-studio.duckdns.org; となっているため、移行期間は 両方受ける（段階移行）：
例：00_base.conf の 80 / 443 両方で
```
server_name yadag-studio.duckdns.org ops.yadag.fyi;
```
※最終的に 移行前のドメインを捨てる際は移行前のドメインを外す。

2) 先に “サーバ側が受けられる状態” をテスト（DNS待ち無し）

Cloudflareの反映を待たずに、--resolve でサーバ直当て確認：
```
# グローバルIPv4に固定して疎通（DNSを経由しない）

curl -sv --connect-timeout 2 --max-time 10 \
  --resolve ops.yadag.fyi:443:<ChronosのグローバルIPv4> \
  https://ops.yadag.fyi/healthz -o /dev/null
```
ここで 200 が返るようにする。

## certbot（証明書の再発行・更新フロー）
### 方針
- ops.yadag.fyi の証明書を Let’s Encrypt で取得する。
- 取得後、nginx の ssl_certificate / ssl_certificate_key を ops.yadag.fyi 側へ切り替える。
- 更新フロー（systemd timer / deploy-hook）は従来通り、ただし対象ドメイン名が変わる。

### 手順（概要）
1. ops.yadag.fyi 用に LE 証明書を発行。
2. nginx が参照する証明書パスを .../live/ops.yadag.fyi/ に変更。
3. nginx -t → reload
4. 外部から https://ops.yadag.fyi/healthz を叩いて SAN/CN を確認。

### 発行時の重要条件（HTTP-01）
- `http://ops.yadag.fyi/.well-known/acme-challenge/...` が外部から到達できる必要がある。
- 既に /.well-known/acme-challenge/ は auth off & webroot なので、そのまま使える想定。

### 更新フロー（既存の仕組みを維持）
- certbot renew を systemd timer で定期実行。
- `--deploy-hook`で `reload-devops-proxy.sh` を呼ぶ。
- これにより証明書更新後に nginx reload が走る

#### timer/serviceの確認
```
systemctl list-timers --all | rg -i 'certbot|letsencrypt|acme'
systemctl list-unit-files | rg -i 'certbot|letsencrypt|acme'
```
中身の確認
```
systemctl cat certbot-renew.timer
# Timer: certbot-renew.timer（daily / RandomizedDelaySec=1h / Persistent=true）
```
```
systemctl cat certbot-renew.service
# Service: certbot-renew.service
```

deploy-hook の実体
```
rg -n --no-messages 'deploy-hook|reload-devops-proxy|certbot renew' \
  /etc/systemd/system /usr/lib/systemd/system /usr/local/bin /etc/cron* 2>/dev/null
# deploy-hookスクリプト: /usr/local/bin/reload-devops-proxy.sh
```

##### Renewコマンド:
```
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook /usr/local/bin/reload-devops-proxy.sh
```

### 詳細手順
- server_nameの80ポートを新ドメインに変更
- Chronosで以下を実行してNginxを再起動
```
docker exec -it devops-studio-proxy-devops-proxy-1 nginx -t
docker exec -it devops-studio-proxy-devops-proxy-1 nginx -s reload
```

- certbotで証明書の新規発行(webroot方式)
```
sudo mkdir -p /home/chronos/workspace/_acme/.well-known/acme-challenge
sudo chown -R chronos:chronos /home/chronos/workspace/_acme

sudo certbot certonly --webroot \
  -w /home/chronos/workspace/_acme \
  -d ops.yadag.fyi
```

- 発行できたか確認
```
sudo ls -l /etc/letsencrypt/live/ops.yadag.fyi/
```

- 443 の server block を ops に切り替え（証明書パスも）
- 00_base.conf の :443 側を ops にして、証明書パスも ops に合わせる：
   - server_name ops.yadag.fyi;
   - ssl_certificate /etc/letsencrypt/live/ops.yadag.fyi/fullchain.pem;
   - ssl_certificate_key /etc/letsencrypt/live/ops.yadag.fyi/privkey.pem;

Nginxの再起動
```
docker exec -it devops-studio-proxy-devops-proxy-1 nginx -t
docker exec -it devops-studio-proxy-devops-proxy-1 nginx -s reload
```

- 外部から200確認（CN/SANも確認）
Proxied をOFF（DNS only）にしてる間は、普通に外から見ればOK：
```
curl -sv --max-time 10 https://ops.yadag.fyi/healthz -o /dev/null
```

CN/SANを確認
```
curl -sv --max-time 10 https://ops.yadag.fyi/healthz -o /dev/null
echo | openssl s_client -connect ops.yadag.fyi:443 -servername ops.yadag.fyi 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

- CloudflareをProxied ONに戻す
※証明書発行と確認が終わったらDNSレコードのProxiedをONに戻す。

## UptimeRobot 側の変更点
- 監視先を yadag-studio.duckdns.org → ops.yadag.fyi に変更
- 監視対象URL：
   - https://ops.yadag.fyi/healthz
   - https://ops.yadag.fyi/_internal/healthz
   - https://ops.yadag.fyi/_internal/upstream/delay-api
- 監視間隔は現状のまま（まずはDNS/経路安定化の効果を見る）
- 誤検知が残る場合は、次段で以下を検討：
   - 監視間隔/タイムアウトの調整
   - Cloudflare 側の WAF/Rate Limit の影響確認

## 検証手順
1) 内部（devops-edge経由）
```
docker run --rm --network devops-edge curlimages/curl:8.6.0 -sS -w "\n%{http_code}\n" \
  http://devops-proxy:18080/healthz
```

NOTE: Cloudflare Proxied ON の場合、クライアントから見える証明書は Cloudflare 側（例: *.yadag.fyi）になる。Origin の Let’s Encrypt 証明書を確認したい場合は一時的に DNS only にするか、--resolve で Origin IP へ直当てする。

2) 外部（CloudflareでProxied ONでも確認できる期待値チェック）
```
curl -sv --connect-timeout 2 --max-time 10 https://ops.yadag.fyi/healthz -o /dev/null
curl -sv --connect-timeout 2 --max-time 10 https://ops.yadag.fyi/_internal/healthz -o /dev/null
curl -sv --connect-timeout 2 --max-time 10 https://ops.yadag.fyi/_internal/upstream/delay-api -o /dev/null
```

 `/_internal/healthz` と `/_internal/upstream/delay-api` は監視用途のため `auth_basic off` を明示しており、外部からも **200** が返るのが想定。
一方で、それ以外の `/_internal/*` は 00_base.conf のデフォルト保護（Basic認証）により **401** になるのが想定。
```
# 想定: 200（監視用に auth off）
curl -sS -o /dev/null -w "internal healthz code=%{http_code}\n" \
  https://ops.yadag.fyi/_internal/healthz

# 想定: 200（監視用に auth off）
curl -sS -o /dev/null -w "internal upstream delay-api code=%{http_code}\n" \
  https://ops.yadag.fyi/_internal/upstream/delay-api

# 想定: 401（= /_internal のデフォルト保護が効いている確認）
curl -sS -o /dev/null -w "internal protected sample code=%{http_code}\n" \
  https://ops.yadag.fyi/_internal/should-be-protected
```

3) flap 再現テスト
```
HOST=ops.yadag.fyi
for i in {1..60}; do
  echo "=== $(date -Is) ==="
  for path in /healthz /_internal/healthz /_internal/upstream/delay-api; do
    curl -sS --connect-timeout 2 --max-time 10 \
      -o /dev/null \
      -w "${path} code=%{http_code} total=%{time_total} dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} start=%{time_starttransfer}\n" \
      "https://${HOST}${path}" || echo "${path} FAIL"
  done
  sleep 1
done
```

## 切り戻し手順（移行前ドメインへ戻す場合）
### 目的
移行後に外部到達性が悪化する／証明書が想定通りにならない等の際に、即座に旧経路へ戻す。

#### 切り戻し（最短）
1. UptimeRobot の監視先を ops.yadag.fyi → yadag-studio.duckdns.org に戻す
2. nginx の server_name を DuckDNS のみに戻す（または両方受けのままでも可）
3. nginx の ssl_certificate を DuckDNS 証明書へ戻す（切替していた場合）
4. nginx -t → reload
5. curl -sv https://yadag-studio.duckdns.org/healthz で 200 を確認

#### Cloudflare の後片付け（任意）
- ops の DNS レコードを削除、または DNS only に切り替え
（“復旧優先”なら後回しでOK）

## 付記：monitor（内部監視）への影響
- monitor は BASE=http://devops-proxy:18080 に固定し、外部DNS/外部経路の揺れに影響されないようにする
- 外部経路の死活は UptimeRobot で担保する（責務分離）

