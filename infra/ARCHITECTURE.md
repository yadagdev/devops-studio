# ARCHITECTURE
## 1. Purpose
DevOps-Studio は、個人開発および小規模チーム向けの 「自宅マルチマシン + GitHub + ローカルLLM」を前提とした統合開発環境

このドキュメントは、新しくこの環境を触る自分（未来の自分を含む）やコラボレーターが、 **どのマシンで何をしていて、どこを変更すれば何が起きるか** を素早く理解できることを目的としている

- コード管理・CI/CD・デプロイを一元化し、プロジェクトごとにバラバラな運用を避ける
- self-hosted runner (AlmaLinux) を活用して、ローカル LAN 内だけで完結する開発フローを実現する
- 将来的に複数の Web アプリ / API を同じ基盤上で運用できる状態を作る

---

## 2. System Overview
### 2.1 ノード構成
- **Chronos (AlmaLinux 10.1)**
  - 役割: 本番サーバー / 統合開発サーバー
  - 機能:
     - Webアプリの本番運用
     - Nginx + リバースプロキシ + Let's Encrypt 統合ポイント
     - docker/docker-composeによるアプリ本番ホスト
     - GitHub self-hosted runner (actions-runner)
- **Astraeus (Mac mini M4 Pro)**
  - 役割: メイン開発マシン
  - 機能:
     - コーディング
     - ローカルLLMによるコード生成+設計支援
     - 初期検証
- **Selene (Mac mini M4 Pro)**
  - 役割: テスト・レビュー専用
  - 機能: 
     - E2Eテスト(Playwright)
     - 静的解析
     - ローカルLLMによるコードレビュー

- **Windows (i9-14900KF + RTX 4070 SUPER)**
  - 役割: SRE / 重ビルド / GPUテスト
  - 機能:
     - 重いビルド
     - GPU負荷テスト
     - 将来的な高性能LLMモデルの実験（動かせる範囲で）
  
全て同一LAN上にあり、相互に SSH 接続可能であることを前提とする。
  
---

## 3. Component
- **GitHub**
  - すべてのアプリケーションリポジトリのコード管理
  - DevOps-Studio 自体のリポジトリ (`devops-studio`)

- **DevOps-Studio**
  - 共通ドキュメント (ARCHITECTURE, PROJECT_CHARTER, Coding Guidelines)
  - CI / CD テンプレート (`templates/ci/*.yml`)
  - Docker Compose テンプレート (`templates/docker-compose.*.yml`)

- **アプリケーションリポジトリ**
  - 例: `todo-auth-app`, `some-api`, etc.
  - 各リポで devops-studio のテンプレートをコピー/カスタマイズして利用

---

## 4. Self-hosted Runner (AlmaLinux)
運用サーバーであるAlmaLinux 上に GitHub Actions の self-hosted runner を配置し、`runs-on: self-hosted` のジョブをすべて AlmaLinux で処理する。

- runner 配置ディレクトリ例: `/home/chronos/actions-runner`

- サービス化:
  - `./config.sh ...`
  - `sudo ./svc.sh install`
  - `sudo ./svc.sh start`

- ラベル運用: - 現時点ではデフォルトの `self-hosted, Linux, X64` のみ
  - 将来的に `chronos`, `gpu`, `build` などを追加する余地を残す

self-hosted runner により、以下が可能になる:
  - GitHub 上のワークフローを **LAN 内のサーバーだけ**で実行
  - Docker Compose を直接 Chronos 上で叩いてデプロイ
  - 公開用サーバーと CI 実行環境を同一マシンに集約（個人開発にとって運用コスト最小）
  
---

## 5. Repositories
### 5.1 devops-studio (このリポジトリ)
- 種別: インフラ / メタリポジトリ
  - 主なディレクトリ:
    - `infra/` : アーキテクチャドキュメント, 図, IaC テンプレ
    - `.github/workflows/` : CI/CD 定義
    - `docker/` : 本番用 docker-compose, nginx 設定 など
    
### 5.2 アプリケーション系リポジトリ（例）
- `todo-app` / `llm-helper-app` など
- 各アプリは独立リポジトリとし、共通の GitHub Actions テンプレを利用する。
 
---

## 6. Standard Deployment Procedure
### 6.1 アプリ側の前提
各アプリケーションリポジトリは以下を前提とする:
  - `main` ブランチ = 本番相当
    - リポジトリ直下に `docker-compose.yml` を用意
    - 必要に応じて devops-studio の
      - `templates/docker-compose.webapp.yml`
      - `templates/docker-compose.db.yml`
      - `templates/docker-compose.proxy.yml`
    をベースに構成する
  - AlmaLinux（Chronos） 上のデプロイ先:
    - `/home/chronos/apps/<app-name>`
  
### 6.2 デプロイフロー (GitHub Actions 経由)
  1. 開発者がローカルで `develop` ブランチに実装・テスト
  2. GitHub に push → `ci-node.yml` / `ci-python.yml` による CI 実行
  3. `develop` → `main` への Pull Request を作成
  4. CI が Green になり、レビューを通過したら `main` にマージ
  5. `main` への push をトリガーに `deploy-docker.yml` が起動
     - `runs-on: self-hosted`
     - working-directory: `/home/chronos/apps/<app-name>`
     - `docker compose up -d --build` を実行
  
---

## 7. Runtime Topology
### 7.1 通常の開発フロー
  1. **Astraeus**
     - feature ブランチを作成し、実装・ローカル動作確認
     - コミット → GitHub の該当リポジトリへ push

  2. **GitHub Actions (CI)**
     - push / PR をトリガーに CI 実行（lint, unit test）

  3. **Selene** - 必要に応じてローカルで E2E / UI テストを追加実行
     - LLM レビューモデルでコード・設計レビューを行い、PR にコメント

  4. **Windows** - 重いビルド / 負荷テスト / GPU 依存タスクを実行
     - 問題なければ main ブランチへのマージ、あるいは release タグ作成

  5. **Chronos**
     - Chronos でdocker-compose による本番更新を実行
     - Chronosは Actions runner と本番コンテナ稼働の場
     - デプロイの発火条件は 8.3 を参照
     - self-hosted runner 上で実行されるため、本番デプロイに SSH 接続は不要
     - .env をデプロイ先ディレクトリに持つ(.env.localはアプリ側リポジトリで所有)
    
---

## 8. CI/CD Pipeline
### 8.1 ブランチ戦略
基本は Git-Flow をベースにした以下の構成とする：
  - `main`
    - 本番運用ブランチ。Chronos 上で動いているコードのソース・オブ・トゥルース。
    - 原則として直接コミットしない。`release/*` または `hotfix/*` からのマージのみ。

  - `develop`
    - 開発統合ブランチ。日常開発の最新状態。
    - `feature/*` や `fix/*` をここにマージしていく。
    - 新機能・修正は基本的にここから派生。

  - `feature/*`
    - 新機能開発用ブランチ。命名例：
      - `feature/todo-api`
      - `feature/llm-integration`
    - `develop` から派生し、完了したら `develop` にマージ。

  - `fix/*` - 開発中に見つかったバグ修正用ブランチ。
    - 命名例: `fix/login-validation` など。
    - 原則として修正対応完了後 `develop` にマージ
    - `develop` から派生させる。

  - `release/*`
    - 本番リリース準備用ブランチ。
    - 例：`release/1.2.0`
    - リリース単位で `develop` から切り、軽微な修正のみここで行う。
    - リリース時に `main` にマージし、そのコミットにタグ（`v1.2.0` など）を付ける。
    - `develop` にもマージバックする。

  - `hotfix/*`
    - 本番環境（`main`）で見つかった致命的バグ修正用ブランチ。
    - `main` から直接派生し、修正後は `main` と `develop` （必要なら `release/*`）の両方にマージする。
    - 命名例: `hotfix/production-500-error`

  - `main` は常に「デプロイ可能」な状態を維持

  - `develop` で日々の開発を回しつつ、リリースタイミングでは `release/*` で安定化できる

  - ブランチ名は CI のトリガー条件（`ci-node.yml` / `ci-python.yml`）と一致する
  
### 8.2 CI (Continuous Integration)
  - 実行場所: GitHub Actions（ホストランナー or 自前ランナー）
  - 主なジョブ: - Node.js での lint / unit test
  - Playwright による最低限の E2E（必要に応じて）
  
### 8.3 CD (Continuous Delivery/Deployment)
  - トリガー:
     - **Phase1**: main push をデプロイトリガーとする（タグは記録用途）
     - **Phase2**: タグ push をデプロイトリガーに移行する（main pushではデプロイしない）
       - 流れ:
        **方式A（推奨/現状）**
         1. GitHub Actions（self-hosted runner）が AlmaLinux 上でリポジトリを checkout
         2. AlmaLinux 上で docker compose up -d --build を実行
         3. nginx 経由で公開

         **方式B（将来/レジストリ導入後）**
          1. GitHub Actions でアプリの Docker イメージをビルド
          2. コンテナレジストリ（将来的に導入予定）へ push
          3. AlmaLinux 上で `docker-compose pull && docker-compose up -d` を実行
          4. nginx 経由で公開
        
---

## 9. Local LLM Integration
### 9.1 ランタイム
- ランタイム:
  **Ollama**
     - 利用ノード:
        - Astraeus: 開発支援（タスク分解, コード生成, 日本語仕様書）
        - Selene: レビュー支援（コードレビュー, テストケース提案）
        - Windows: 将来的な高性能LLMモデルの実験
        
### 9.2 モデル方針
 - 日常用（高速）:
    - **devstral-small-2**
    - **olmo-3**

 - 重い検討用:
    - **gpt-oss-20b**、**gpt-oss-120b**

 - 必要に応じて gpt-oss-120b を Windows で利用

 - 同一モデルでのレビューは行わずモデルによって役割を切り分ける
 
### 9.3 典型的な利用パターン
- `llm-dev-jp-fast`:
  - 仕様整理、タスク分解、型設計レビュー、Playwright テストケース生成

- `llm-dev-deep`:
  - アーキテクチャの検討、リファクタ計画、障害対応の原因分析サポート
  
---

## 10. Technology Stack
- **言語**
  - Node.js: LTS
    - npm: Node.js 同梱版
  - Python: 3.11 系（自動スクリプト・補助ツール用）
  
- **テスト**
  - E2E: Playwright
  - 単体テスト: Vitest 等（各アプリ側で選択）

- **インフラ**
  - OS: AlmaLinux 10.1 (Chronos)
  - コンテナ: Docker, docker-compose
  - Web: nginx + Let’s Encrypt (certbot)
  
---

## 11. Security & Secrets
- GitHub Secrets で管理：
  - `CHRONOS_SSH_KEY`
  - `CHRONOS_SSH_HOST`

- アプリごとの API キー類
  - **方式A（推奨/現状）**: self-hosted runner が Chronos 上で実行し、Chronos ローカルで docker compose を叩く（SSH不要）
  - **方式B（代替）**: GitHub-hosted runner 等から Chronos へ SSH 接続してデプロイする（SSH鍵が必要）
- AlmaLinux 側では `.env` にアプリ設定を集約し、 `.env` 自体は Git 管理しない。

---

## 12. Future Work
- コンテナレジストリ（ローカル or クラウド）の導入
- モニタリング（Prometheus + Grafana など）
- DevOps-Studio 自体の Web UI（状況ダッシュボード）の作成
- CONTRIBUTING.md の整備