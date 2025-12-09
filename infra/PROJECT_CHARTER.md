# DevOps-Studio Project Charter

## 1. プロジェクトの目的

DevOps-Studio は、自宅環境で稼働する以下の要素をまとめて扱うための
**個人向け統合開発・デプロイ基盤**である。

- 複数マシン（Chronos(AlmaLinux) / Astraeus(Mac mini M4 Pro) / Selene(Mac mini M4 Pro) / Windows）
- GitHub + GitHub Actions による CI/CD
- ローカル LLM（Ollama）による開発支援

最終的なゴールは、

- 「ひとりだけど、チーム開発に近いワークフロー」
- 「アジャイルに小さく作って小さく改善できる土台」

を恒常的に提供すること。

---

## 2. スコープ

### 2.1 含まれるもの

- ブランチ戦略（Git-Flow ベース）の整備
- GitHub Actions による CI / CD パイプライン構築
- Chronos 上での本番コンテナ運用（docker-compose）
- ローカル LLM を使った設計・実装・レビュー支援フローの確立
- 将来のアプリケーション（個人サイトやユーティリティ）のデプロイ基盤

### 2.2 現時点で含まれないもの

- 大人数チームを前提とした権限管理・監査ログ
- マルチクラウド・大規模クラスタ（k8s 等）
- 商用 SLA（99.9% など）レベルの可用性・冗長構成

必要になったときに、ここから段階的に広げる。

---

## 3. マシンと役割

- **Chronos (AlmaLinux 10.1)**  
  - 本番サーバー / 統合開発サーバー  
  - nginx + docker-compose でサービスを公開

- **Astraeus (Mac mini M4 Pro / Super)**  
  - メイン開発マシン  
  - コーディング、設計、ローカル LLM によるアイデア出し

- **Selene (Mac mini M4 Pro / Normal)**  
  - テスト・レビュー担当  
  - E2Eテスト（Playwright）、静的解析、LLM によるコードレビュー

- **Windows (i9 + RTX 4070 SUPER)**  
  - SRE / 重ビルド / GPUテスト担当  
  - 負荷の高いビルドや GPU ベンチ、将来の gpt-oss 系モデル検証など

---

## 4. 開発プロセスの前提

- Git ブランチは Git-Flow ベース（main / develop / feature / fix / release / hotfix）
- 原則として main に直接コミットしない
- PR ベースでのマージを行う（自分ひとりでも「レビュー工程」を意識する）
- CI は GitHub Actions で行い、Chronos への CD も Actions から実行する

---

## 5. LLM 利用方針

### 5.1 ランタイム

- ランタイム: Ollama
- 主なモデル:
  - 日常用途: **Llama-3-ELYZA-JP-8B**
  - 重い検討用途: **gpt-oss 系（20b / 120b）**

### 5.2 使い方のルール（暫定）

- 仕様整理・タスク分解・設計のたたき台に積極的に使う
- コード生成は「丸投げ」ではなく、小さい単位で依頼する
- セキュリティや本番に影響が大きい部分は、人間が必ず差分確認する
- LLM の出力は「提案」であり、「決定」ではない

---

## 6. フェーズ

### フェーズ1: 内部向け DevOps-Studio 基盤の完成

- Chronos で Hello World コンテナを docker-compose で公開済み
- GitHub Actions による CI が動作している
- main / develop / feature ブランチ運用が回り始めている
- LLM を日常的に開発支援に使い始めている

### フェーズ2: 個人ページの公開

- 別リポジトリ（例: `personal-site`）で個人ページを作成
- GitHub Actions から Chronos への自動デプロイを構成
- ドメインがなければ一時的に IP または無料ドメイン / サービスで公開

### フェーズ3: 拡張

- 必要に応じて:
  - モニタリング導入
  - コンテナレジストリ導入
  - DevOps-Studio 自体のダッシュボード化
