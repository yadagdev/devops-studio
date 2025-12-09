# DevOps-Studio / infra / ARCHITECTURE.md

## 1. Purpose

DevOps-Studio は、個人開発および小規模チーム向けの
「自宅マルチマシン + GitHub + ローカルLLM」を前提とした統合開発環境である。

このドキュメントは、新しくこの環境を触る自分（未来の自分を含む）やコラボレーターが、
**どのマシンで何をしていて、どこを変更すれば何が起きるか** を素早く理解できることを目的とする。

---

## 2. System Overview

### 2.1 ノード構成

- **Chronos (AlmaLinux 10.1)**
  - 役割: 本番サーバー / 統合開発サーバー
  - 機能: Webアプリの本番運用, nginxリバースプロキシ, docker/docker-compose

- **Astraeus (Mac mini M4 Pro)**
  - 役割: メイン開発マシン
  - 機能: コーディング, ローカルLLMによる設計支援, 初期検証

- **Selene (Mac mini M4 Pro)**
  - 役割: テスト・レビュー専用
  - 機能: E2Eテスト(Playwright), 静的解析, LLMによるコードレビュー

- **Windows (i9 + RTX 4070 SUPER)**
  - 役割: SRE / 重ビルド / GPUテスト
  - 機能: 重いビルド, GPU負荷テスト, 将来的な gpt-oss 系モデルの実験

全て同一LAN上にあり、相互に SSH 接続可能であることを前提とする。

---

## 3. Repositories

### 3.1 devops-studio (このリポジトリ)

- 種別: インフラ / メタリポジトリ
- 主なディレクトリ:
  - `infra/` : アーキテクチャドキュメント, 図, IaC テンプレ
  - `.github/workflows/` : CI/CD 定義
  - `docker/` : 本番用 docker-compose, nginx 設定 など

### 3.2 アプリケーション系リポジトリ（例）

- `todo-app` / `llm-helper-app` など
- 各アプリは独立リポジトリとし、共通の GitHub Actions テンプレを利用する。

---

## 4. Runtime Topology

### 4.1 通常の開発フロー

1. **Astraeus**
   - feature ブランチを作成し、実装・ローカル動作確認
   - コミット → GitHub の該当リポジトリへ push

2. **GitHub Actions (CI)**
   - push / PR をトリガーに CI 実行（lint, unit test）

3. **Selene**
   - 必要に応じてローカルで E2E / UI テストを追加実行
   - LLM レビューモデルでコード・設計レビューを行い、PR にコメント

4. **Windows**
   - 重いビルド / 負荷テスト / GPU 依存タスクを実行
   - 問題なければ main ブランチへのマージ、あるいは release タグ作成

5. **Chronos**
   - release タグをトリガーとして GitHub Actions (CD) が発火
   - Chronos へ SSH 経由で接続し、docker-compose による本番更新を実行

---

## 5. CI/CD Pipeline

### 5.1 ブランチ戦略

基本は Git-Flow をベースにした以下の構成とする：

- `main`  
  - 本番運用ブランチ。Chronos 上で動いているコードのソース・オブ・トゥルース。
  - 原則として直接コミットしない。`release/*` または `hotfix/*` からのマージのみ。

- `develop`  
  - 開発統合ブランチ。日常開発の最新状態。
  - `feature/*` や `fix/*` をここにマージしていく。

- `feature/*`  
  - 新機能開発用ブランチ。命名例：
    - `feature/todo-api`
    - `feature/llm-integration`
  - `develop` から派生し、完了したら `develop` にマージ。

- `fix/*`  
  - 開発中に見つかったバグ修正用ブランチ。
  - 命名例：`fix/login-validation` など。
  - `develop` から派生し、完了したら `develop` にマージ。

- `release/*`  
  - 本番リリース準備用ブランチ。
  - 例：`release/1.2.0`
  - リリース単位で `develop` から切り、軽微な修正のみここで行う。
  - リリース時に `main` にマージし、そのコミットにタグ（`v1.2.0` など）を付ける。
  - 必要に応じて `develop` にもマージバックする。

- `hotfix/*`  
  - 本番環境（`main`）で見つかった致命的バグ修正用ブランチ。
  - `main` から直接派生し、修正後は `main` と `develop` （必要なら `release/*`）の両方にマージする。
  - 命名例：`hotfix/production-500-error`

### 5.2 CI (Continuous Integration)

- 実行場所: GitHub Actions（ホストランナー or 自前ランナー）
- 主なジョブ:
  - Node v25.2.1 での lint / unit test
  - Playwright による最低限の E2E（必要に応じて）

### 5.3 CD (Continuous Delivery/Deployment)

- トリガー:
  - `main` へのマージ
  - あるいは `vX.Y.Z` タグの push
- 流れ:
  1. GitHub Actions でアプリの Docker イメージをビルド
  2. コンテナレジストリ（将来的に導入予定）へ push もしくは Chronos へ直接 SCP
  3. Chronos 上で `docker-compose pull && docker-compose up -d` を実行
  4. nginx 経由で公開

---

## 6. Local LLM Integration

### 6.1 ランタイム

- ランタイム: **Ollama**
- 利用ノード:
  - Astraeus: 開発支援（タスク分解, コード生成, 日本語仕様書）
  - Selene: レビュー支援（コードレビュー, テストケース提案）
  - Windows: 将来的な gpt-oss 系モデルの実験

### 6.2 モデル方針

- 日常用（高速）:
  - **Llama-3-ELYZA-JP-8B**（日本語特化8Bクラス）
- 重い検討用:
  - **gpt-oss-20b** をターゲットとした設計（利用環境が整い次第）
  - 必要に応じて gpt-oss-120b を Windows で実験的に利用

### 6.3 典型的な利用パターン

- `llm-dev-jp-fast`:
  - 仕様整理、タスク分解、型設計レビュー、Playwright テストケース生成
- `llm-dev-deep`:
  - アーキテクチャの検討、リファクタ計画、障害対応の原因分析サポート

---

## 7. Technology Stack

- **言語**
  - Node.js: v25.2.1
  - npm: Node.js 同梱版
  - Python: 3.11 系（自動スクリプト・補助ツール用）

- **テスト**
  - E2E: Playwright
  - 単体テスト: Jest 等（各アプリ側で選択）

- **インフラ**
  - OS: AlmaLinux 10.1 (Chronos)
  - コンテナ: Docker, docker-compose
  - Web: nginx + Let’s Encrypt (certbot)

---

## 8. Security & Secrets

- GitHub Secrets で管理：
  - `CHRONOS_SSH_KEY`
  - `CHRONOS_SSH_HOST`
  - アプリごとの API キー類

- Chronos 側では `.env` にアプリ設定を集約し、
  `.env` 自体は Git 管理しない。

---

## 9. Future Work

- コンテナレジストリ（ローカル or クラウド）の導入
- モニタリング（Prometheus + Grafana など）
- DevOps-Studio 自体の Web UI（状況ダッシュボード）の提供
- 他開発者が参加しやすいよう、CONTRIBUTING.md の整備
