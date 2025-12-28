# Continue/Cursor 運用ドキュメント（DevOps-Studio）

このディレクトリは、DevOps-Studio における Continue/Cursor（ローカルLLM含む）の運用ルール・テンプレを管理する。

## 目的
- 汚さない：本番（Productionホスト）や他環境へ余計な変更を持ち込まない
- 漏らさない：秘密情報（鍵/トークン/URL/ログ等）を Git や外部へ出さない
- 再現性：どの端末でも同じ手順・同じ品質ゲートで回せる

## 目次
- 運用ポリシー：continue-cursor-policy.md

## 関連（Workspace設定）
- Continue の Workspace ルール/プロンプト：/.continue/rules, /.continue/prompt
  - これらは Git 管理する。（ただし許可リスト方式で）
  - ユーザー環境の設定（~/.continue/config.yaml 等）は Git 管理しない。
