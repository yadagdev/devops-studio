# Continue/Cursor（ローカルLLM含む）運用ポリシー

## 1. 目的
DevOps-Studio において Continue/Cursor を使ったローカルLLM運用を、
「汚さない・漏らさない・再現性」を最優先で回すためのルールを定める。

## 2. スコープ
対象：
- Continue（Cursor拡張）
- Cursor（エディタとしての利用）
- ローカルLLMを使った設計・実装案作成・レビュー

対象外：
- 本番（Productionホスト）上での LLM 実行
- 秘密情報の永続化/共有（Git、外部メモ、公開Issue等）

## 3. 役割分離（Role）
LLM運用は、同一モデル・同一視点に偏らないように役割を分ける。

- PoC/Design（提案・実装案の生成）
  - 目的：実装の方向性、パッチ案、テスト観点の叩き台を作る。
- Review（批判的レビュー）
  - 目的：欠陥・仕様逸脱・運用事故・セキュリティ逸脱を見つける。
- Integration（統合・最終判断）
  - 目的：複数レビューを統合し、人間が最終判断する。
- Production（本番反映）
  - 目的：承認済みの変更だけを最小手順で反映し、確認して終える。
  - 原則：Productionホストでは LLM を動かさない / ログを増やさない / 余計なファイルを置かない。

### 付録：DevOps-Studio での割当（愛称）
- PoC/Design：Astraeus
- Review：Selene
- Integration：Windows
- Production：Chronos

※ 愛称自体は機密ではないが、IP/ドメイン/ユーザー名/絶対パス等の侵入に資する情報はこの文書に書かない。

## 4. Git管理するもの / しないもの
### Git管理する（repo配下）
- `/.continue/rules/**`（ルール）
- `/.continue/prompt/**`（プロンプトテンプレ）
- `/infra/llm/continue/**`（運用ドキュメント）

### Git管理しない（ユーザー環境側・秘密混入リスク）
- `~/.continue/config.yaml`（mac） / `C:\Users\<USER>\.continue\config.yaml`（win）
- Cursor ユーザー設定（OS側）
- ログ/履歴/会話/キャッシュ
- モデル実体パス、ローカルLLMの接続先URL、トークン、鍵、Webhook 等

## 5. 情報の取り扱い（漏らさない）
- 秘密情報（鍵/トークン/Webhook/内部URL/個人情報/サーバ詳細）はプロンプトへ貼らない。
- 必要な値は伏せ字にする。（例：`https://example.invalid`、`TOKEN_REDACTED`）
- 生成物（パッチ/レビュー）を Git に残す場合、秘密が混じっていないことを最優先で確認する。

## 6. 生成物のフォーマット（再現性）
- 実装案：原則「変更ファイル一覧 → 差分（patch） → テスト案 → ロールバック案」
- レビュー：原則「重大/中/軽微」＋「理由」＋「再現手順」＋「修正提案」
- 変更種別ゲート：infra/checklists を必ず参照し、該当チェックを通す

## 7. 本番反映（汚さない）
Production反映は最小手順で行う。
- 基本は `git pull` と `docker compose ...` と `curl` 等の確認のみ。
- 本番ホストでの ad-hoc 編集は原則禁止。（必要なら repo に戻して PR で行う。）
- 反映後は external-smoke / 内部監視 / UptimeRobot を確認して完了。

## 8. インシデント発生時の初動（概要）
- 直ちに漏洩経路を止める（公開物削除/アクセス遮断）
- 鍵/トークン/Webhook のローテーション
- ログ/履歴の確認（機密が残っていないか）
- 再発防止（プロンプト/テンプレ更新）
