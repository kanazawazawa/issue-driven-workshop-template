# ワークショップ管理スクリプト

このフォルダには、ワークショップ環境を管理するためのスクリプトが含まれています。

---

## 📋 前提条件

### 必要なツール

| ツール | 用途 | インストール |
|--------|------|-------------|
| **Azure CLI** | Azure リソース管理 | [インストール手順](https://docs.microsoft.com/ja-jp/cli/azure/install-azure-cli) |
| **GitHub CLI** | リポジトリ・シークレット管理 | [インストール手順](https://cli.github.com/) |

### ログイン

```powershell
# Azure にログイン
az login

# GitHub にログイン
gh auth login
```

---

## 🏗️ Azure 基盤リソースの作成（初回のみ）

スクリプトを実行する前に、以下の Azure リソースを作成してください。

```powershell
# 変数を設定（任意の名前に変更可）
$location = "swedencentral"
$resourceGroup = "rg-myworkshop"
$appServicePlan = "plan-myworkshop"
$storageAccount = "samyworkshopstorage"  # 英小文字+数字のみ、3-24文字、グローバルで一意

# 1. リソースグループを作成
az group create --name $resourceGroup --location $location

# 2. App Service プランを作成（B1 = Basic。参加者数に応じてスケール変更）
az appservice plan create --name $appServicePlan --resource-group $resourceGroup --location $location --sku B1

# 3. ストレージアカウントを作成
az storage account create --name $storageAccount --resource-group $resourceGroup --location $location --sku Standard_LRS

# 4. 接続文字列を取得（config.json に設定する値）
az storage account show-connection-string --name $storageAccount --resource-group $resourceGroup --query connectionString -o tsv
```

> 💡 テーブルはアプリが初回アクセス時に自動作成されるため、手動作成は不要です。

---

## 🐙 テンプレートリポジトリの準備（初回のみ）

1. GitHub でテンプレート用リポジトリを作成（例: `issue-driven-workshop-template`）
2. リポジトリの **Settings** → **General** → **"Template repository"** にチェック ✅
3. `config.json` の `github.templateRepo` にこのリポジトリを指定

---

## ⚙️ 初期設定

### 1. 設定ファイルを作成

```powershell
cd _admin
Copy-Item config.json.template config.json
```

### 2. `config.json` を編集

```json
{
  "azure": {
    "resourceGroup": "rg-myworkshop",
    "appServicePlan": "plan-myworkshop",
    "webAppNamePrefix": "app-workshop",
    "connectionString": "<Azure Table Storage の接続文字列>",
    "tableNamePrefix": "Expenses"
  },
  "github": {
    "owner": "<GitHub ユーザー名 or 組織名>",
    "templateRepo": "<owner>/issue-driven-workshop-template",
    "repoPrefix": "issue-driven-workshop",
    "visibility": "public"
  }
}
```

> ⚠️ `config.json` にはシークレットが含まれるため、`.gitignore` で除外されています。

---

## 📁 スクリプト一覧

| ファイル | 用途 | 説明 |
|----------|------|------|
| `setup-participant.ps1` | 受講者環境を一括作成 | Web App + リポジトリ + シークレット + デプロイ |
| `create-workshop-webapp.ps1` | Web App のみ作成 | 単体で Web App を作成したい場合 |
| `delete-workshop-webapp.ps1` | Web App を削除 | クリーンアップ用 |
| `cleanup-participant.ps1` | 環境を一括削除 | Web App + リポジトリを削除 |

---

## 🚀 使い方

### 受講者環境を作成（推奨）

```powershell
cd _admin
./setup-participant.ps1 -Number "01"
```

#### 実行内容

1. Azure Web App を作成
2. アプリ設定を構成（接続文字列、テーブル名、64ビット）
3. テンプレートからリポジトリを作成
4. GitHub Actions シークレット/変数を設定
5. 初回デプロイをトリガー

#### 作成されるリソース（デフォルト設定の場合）

| リソース | 命名規則 | 例 |
|----------|----------|-----|
| Web App | `{webAppNamePrefix}-{Number}` | `app-workshop-01` |
| リポジトリ | `{repoPrefix}-{Number}` | `issue-driven-workshop-01` |
| テーブル | `{tableNamePrefix}{Number}` | `Expenses01` |

---

### Web App のみ作成

```powershell
./create-workshop-webapp.ps1 -Number "01"
```

### Web App を削除

```powershell
./delete-workshop-webapp.ps1 -Number "01"
```

### 環境を一括削除（Web App + リポジトリ）

```powershell
./cleanup-participant.ps1 -Number "01"
```

---

## 🔄 ワークフロー

### 新規ワークショップの準備

```powershell
# 1. Azure にログイン
az login

# 2. GitHub にログイン
gh auth login

# 3. config.json を設定
Copy-Item config.json.template config.json
# config.json を編集...

# 4. 受講者数分のセットアップを実行
./setup-participant.ps1 -Number "01"
./setup-participant.ps1 -Number "02"
./setup-participant.ps1 -Number "03"
```

### ワークショップ後のクリーンアップ

```powershell
# 各参加者の Web App + リポジトリを削除
./cleanup-participant.ps1 -Number "01"
./cleanup-participant.ps1 -Number "02"
./cleanup-participant.ps1 -Number "03"
```

### Azure 基盤リソースの削除（すべて不要になった場合）

```powershell
# リソースグループごと削除（中の全リソースが削除されます）
az group delete --name rg-myworkshop --yes --no-wait
```

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
2. **Web App 名はグローバルで一意**: 同じ名前の Web App は作成できません
3. **config.json は Git 管理外**: シークレットを含むため `.gitignore` で除外済み

---

## 🔧 トラブルシューティング

| エラー | 対処 |
|--------|------|
| `Please run 'az login'` | `az login` を実行 |
| `Not logged into any GitHub hosts` | `gh auth login` を実行 |
| `The plan 'plan-xxx' doesn't exist` | `az account show` でサブスクリプションを確認 |
| `InvalidResourceName` | テーブル名にハイフンや特殊文字がないか確認 |
| `config.json not found` | `config.json.template` をコピーして設定 |
