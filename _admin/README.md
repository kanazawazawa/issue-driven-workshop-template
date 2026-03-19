# ワークショップ管理スクリプト

このフォルダには、ワークショップ環境の作成・削除を自動化するスクリプトが含まれています。

---

## 📋 前提条件

### 必要なツール

| ツール | 用途 | インストール |
|--------|------|-------------|
| **Azure CLI** | Azure リソース管理 | [インストール手順](https://docs.microsoft.com/ja-jp/cli/azure/install-azure-cli) |
| **GitHub CLI** | リポジトリ・シークレット管理 | [インストール手順](https://cli.github.com/) |

### ログイン

```powershell
az login
gh auth login
```

### テンプレートリポジトリの準備（初回のみ）

1. GitHub でテンプレート用リポジトリを用意（このリポジトリ自体をテンプレートにする場合も OK）
2. リポジトリの **Settings** → **General** → **"Template repository"** にチェック ✅

---

## 🚀 ワンクリックで全自動セットアップ

```powershell
cd _admin
./init-workshop.ps1 -ParticipantCount 5
```

これだけで以下がすべて自動実行されます：

1. Azure リソース作成（リソースグループ、App Service プラン、ストレージアカウント）
2. 接続文字列を取得して `config.json` を自動生成
3. 参加者ごとに Web App + リポジトリ + シークレット設定 + 初回デプロイ

> 💡 参加者リポジトリからは `_admin/` フォルダが自動的に削除されます。参加者にはノイズにならないよう配慮されています。

### 確認画面の例

```
Workshop Setup Plan
========================================

Participants     : 5
Location         : swedencentral
Resource Group   : rg-workshop-et1xz0        ← ランダムサフィックス
App Service Plan : plan-workshop-et1xz0 (P0v4)
Storage Account  : saworkshopet1xz0
Web App Prefix   : app-workshop-et1xz0
GitHub Owner     : kanazawazawa               ← 自動検出
Template Repo    : kanazawazawa/issue-driven-workshop-template
Repo Prefix      : workshop-et1xz0
Visibility       : public

Proceed? (yes/no):
```

すべてのリソース名にはランダムサフィックスが付与され、複数回実行しても衝突しません。

### 作成されるリソース

| リソース | 命名規則 | 例 |
|----------|----------|-----|
| Resource Group | `rg-workshop-{suffix}` | `rg-workshop-et1xz0` |
| App Service Plan | `plan-workshop-{suffix}` | `plan-workshop-et1xz0` |
| Storage Account | `saworkshop{suffix}` | `saworkshopet1xz0` |
| Web App | `app-workshop-{suffix}-{Number}` | `app-workshop-et1xz0-01` |
| GitHub リポジトリ | `workshop-{suffix}-{Number}` | `workshop-et1xz0-01` |
| Table | `Expenses{Number}` | `Expenses01` |

### カスタマイズ例

```powershell
# リージョンやSKUを変更する場合
./init-workshop.ps1 -ParticipantCount 10 -Location "japaneast" -Sku "B1"

# リソース名を指定する場合（サフィックスなし）
./init-workshop.ps1 -ParticipantCount 3 -ResourceGroup "rg-myteam" -WebAppNamePrefix "app-myteam" -RepoPrefix "myteam-workshop"
```

---

## 🧹 ワンクリックで全削除

```powershell
# 全参加者の環境を一括削除（Web App + リポジトリ）
./destroy-workshop.ps1 -ParticipantCount 5

# Azure 基盤リソースも含めてすべて削除する場合
./destroy-workshop.ps1 -ParticipantCount 5 -DeleteAzureResources
```

確認プロンプトで `destroy` と入力して実行します。

---

## 📁 スクリプト一覧

| ファイル | 用途 | 説明 |
|----------|------|------|
| **`init-workshop.ps1`** | **🚀 全自動セットアップ** | Azure 基盤作成 → config 生成 → 全参加者環境構築 |
| **`destroy-workshop.ps1`** | **🧹 全自動削除** | 全参加者環境 + Azure 基盤を一括削除 |
| `setup-participant.ps1` | 受講者環境を個別作成 | `config.json` が必要 |
| `cleanup-participant.ps1` | 受講者環境を個別削除 | `config.json` が必要 |
| `create-workshop-webapp.ps1` | Web App のみ作成 | `config.json` が必要 |
| `delete-workshop-webapp.ps1` | Web App のみ削除 | `config.json` が必要 |

> 💡 個別スクリプトは `init-workshop.ps1` が生成した `config.json` を使います。
> 参加者の追加・削除など、部分的な操作が必要な場合に使用してください。

---

## ⚙️ config.json について

`init-workshop.ps1` を使う場合は **自動生成** されるため、手動作成は不要です。

個別スクリプトだけを使う場合は、手動で作成してください：

```powershell
Copy-Item config.json.template config.json
# config.json を編集
```

> ⚠️ `config.json` にはシークレット（接続文字列）が含まれるため、`.gitignore` で除外されています。

---

## 📝 GitHub Actions に設定される値

各受講者リポジトリに自動設定されます：

| 種類 | 名前 | 内容 |
|------|------|------|
| Variable | `AZURE_WEBAPP_NAME` | Web App の名前 |
| Secret | `AZURE_WEBAPP_PUBLISH_PROFILE` | 発行プロファイル（XML） |

---

## ⚠️ 注意事項

1. **テーブル名にハイフン不可**: Azure Table Storage のテーブル名には英数字のみ使用可能
2. **Web App 名はグローバルで一意**: ランダムサフィックスにより自動回避
3. **config.json は Git 管理外**: シークレットを含むため `.gitignore` で除外済み
4. **テンプレートリポジトリは事前に準備が必要**: Settings で "Template repository" を有効化

---

## 🔧 トラブルシューティング

| エラー | 対処 |
|--------|------|
| `Please run 'az login'` | `az login` を実行 |
| `Not logged into any GitHub hosts` | `gh auth login` を実行 |
| `The plan 'plan-xxx' doesn't exist` | `az account show` でサブスクリプションを確認 |
| `InvalidResourceName` | テーブル名にハイフンや特殊文字がないか確認 |
| `config.json not found` | `init-workshop.ps1` を使うか、テンプレートからコピーして設定 |
| リポジトリ作成でエラー | テンプレートリポジトリが "Template repository" に設定されているか確認 |
