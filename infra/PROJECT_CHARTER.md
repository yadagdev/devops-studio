# DevOps-Studio Project Charter

## 1. プロジェクトビジョン

DevOps-Studio は、自宅環境で稼働する以下の要素をまとめて扱うための**個人向け統合開発・デプロイ基盤**
「自宅 DevOps 基盤」を構築し、新しいアプリケーションを **素早く、安心して、何度でもリリースできる** 状態を作る

- 新しいアプリを作るときに「毎回 CI/CD や Docker をゼロから組み立て直す」世界から卒業する
- ローカルLLMの力を最大限活用しつつ、最終的なコントロールは人が握る
- 複数マシン前提(yadagの自宅環境)（Chronos(AlmaLinux) / Astraeus(Mac mini M4 Pro) / Selene(Mac mini M4 Pro) / Windows）
- GitHub + GitHub Actions による CI/CD

最終的なゴールは、

- 「ひとりだけど、チーム開発に近いワークフロー」
- 「アジャイルに小さく作って小さく改善できる土台」

を恒常的に提供すること

---

## 2. スコープ

### 2.1 含まれるもの

- ブランチ戦略（Git-Flow ベース）の整備
- GitHub を前提としたコード管理フロー
- GitHub Actions + Chronos(自宅サーバー) self-hosted runner による CI/CD
- Docker / Docker Compose を前提としたアプリケーションデプロイ
- ローカル LLM を使った設計・実装・レビュー支援フローの確立
- アプリ開発に関する標準テンプレートの提供
  - CI テンプレート (`templates/ci/*.yml`)
  - Docker Compose テンプレート (`templates/docker-compose.*.yml`)
- アーキテクチャ / 運用ポリシーのドキュメント化
  - `infra/ARCHITECTURE.md`
  - `PROJECT_CHARTER.md`
  - Coding / Testing Guidelines

### 2.2 現時点で含まれないもの

- 大人数チームを前提とした権限管理・監査ログ
- マルチクラウド・大規模クラスタ（k8s 等）
- 商用 SLA（99.9% など）レベルの可用性・冗長構成

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

## 5. アプリ開発ワークフローの運用方針

### 5.1 新規アプリ開始手順

1. **GitHub で新規リポジトリ作成**
   - 例: `todo-auth-app`
2. **ローカルで clone**（主に Astraeus 上）
3. **開発言語・スタックを決定**
   - 例: Node / Next.js + Express
4. **テンプレ適用**
   - `devops-studio/templates/docker-compose.*.yml` を参考に `docker-compose.yml` を作成
   - `devops-studio/templates/ci/ci-node.yml` をベースに `.github/workflows/ci.yml` を作成
   - `devops-studio/templates/ci/deploy-docker.yml` をベースに `.github/workflows/deploy.yml` を作成
5. **ブランチ戦略を設定**
   - `main`, `develop`, `feature/*`, `fix/*`, `release/*`
6. **Chronos 上のデプロイ先ディレクトリを作成**
   - `/home/chronos/apps/<app-name>`
   - 必要なら `git clone` しておく or Actions から直接 checkout させる

---

## 6. LLM 利用方針

### 6.1 ランタイム

- ランタイム: Ollama
- 主なモデル:
  - 日常用途: **devstral-small-2** 、**olmo-3**
  - 重い検討用途: **gpt-oss 系（20b / 120b）**
- 方針:
  - 設計・雛形生成・テストコード生成など「機械で回せる部分」を LLM に任せる
  - 最終的な仕様・インタフェース・セキュリティに関する判断は人間が行う
- DevOps-Studio のドキュメント（ARCHITECTURE, CHARTER, Coding Guidelines）は LLM への「制約条件」としても活用する

### 6.2 使い方のルール（暫定）

- 仕様整理・タスク分解・設計のたたき台に積極的に使う
- コード生成は「丸投げ」ではなく、小さい単位で依頼する
- セキュリティや本番に影響が大きい部分は、人間が必ず差分確認する
- LLM の出力は「提案」であり、「決定」ではない

---

## 7. 開発サイクル

### 7.1 日々の開発サイクル

1. Astraeus で開発開始
   - Cursor + Ollama を使って設計・実装を進める
   - ブランチは原則 `feature/*` or `fix/*`
2. ローカルで lint / test を実行
   - `npm run lint`
   - `npm test`
3. GitHub に push
   - `develop` 向けの Pull Request を作成
4. CI 実行
   - `ci.yml` が自動で走り、lint / test / build をチェック
5. Selene 側でコードレビュー
   - 必要であれば Selene 上の Cursor + Ollama でレビュー支援
6. 問題なければ `develop` にマージ
7. リリース準備が整ったら `release/*` or 直接 `main` へ PR
8. `main` マージ時に `deploy.yml` が起動し、Chronos 上にデプロイ

---

### 7.2 不具合対応フロー

1. `main` で発見されたバグの場合:
   - `fix/<issue-name>` ブランチを `main` から切る
2. 修正後:
   - `main` への PR を作成し、CI が Green であればマージ
   - 必要であれば同じ修正を `develop` にも適用（`cherry-pick` or `merge`）
3. デプロイは `main` への push をトリガーに自動実行

---

## 8. ロードマップ（ざっくり）

1. DevOps-Studio のテンプレ / CI / ドキュメントを安定させる
2. 認証付き Todo アプリなど、シンプルだがフルスタックなアプリを 1 つ乗せる
3. 再利用可能なパターンを抽出し、テンプレをブラッシュアップする
4. 必要に応じて:
   - Nginx + Let’s Encrypt による HTTPS 化
   - 外部公開 (ポートフォワード / Cloudflare Tunnel など)
   - 監視・ログ収集の追加