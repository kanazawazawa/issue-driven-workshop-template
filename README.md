# IssueDrivenWorkshop

Blazor Server アプリケーションのサンプルプロジェクトです。Azure Table Storage を使用した経費申請システムを実装しています。

## 技術スタック

- **フレームワーク**: Blazor Server (.NET 8)
- **データストア**: Azure Table Storage

## セットアップ

### 1. リポジトリをクローン

```bash
git clone https://github.com/your-username/IssueDrivenWorkshop.git
cd IssueDrivenWorkshop
```

### 2. 設定ファイルを作成

テンプレートファイルをコピーして、Azure Table Storage の接続情報を設定してください。

```bash
cp appsettings.Development.json.template appsettings.Development.json
```

`appsettings.Development.json` を編集し、ストレージアカウント名とテーブル名を設定：

```json
{
  "AzureTableStorage": {
    "StorageAccountName": "<YOUR_STORAGE_ACCOUNT_NAME>",
    "TableName": "Expenses"
  }
}
```

> 💡 本番環境では Managed Identity で認証します。ローカル開発時は `az login` で認証してください。

### 3. アプリケーションを実行

```bash
dotnet run
```

ブラウザで `https://localhost:7123` にアクセスしてください。

## プロジェクト構成

```
IssueDrivenWorkshop/
├── Components/
│   ├── Pages/          # Razorページ
│   ├── Layout/         # レイアウトコンポーネント
│   └── _Imports.razor  # 共通インポート
├── Models/             # エンティティモデル
├── Services/           # ビジネスロジック・データアクセス
└── wwwroot/            # 静的ファイル
```

## 開発ガイドライン

[.github/copilot-instructions.md](.github/copilot-instructions.md) を参照してください。

## CI/CD（GitHub Actions）

### 本番デプロイ

`main` ブランチへの push 時、または手動トリガーで Azure App Service にデプロイされます（OIDC 認証）。

### PR プレビュー環境

Pull Request を作成すると、Azure Deployment Slots にプレビュー環境が自動作成されます。PR コメントにプレビュー URL が通知され、PR クローズ時に自動削除されます。

### セットアップ手順

> 💡 `_admin/init-workshop.ps1` を使う場合、以下は自動設定されます。

1. **Azure App Service を作成**
2. **Service Principal を作成し、OIDC フェデレーション資格情報を設定**
3. **GitHub に登録**: リポジトリ → Settings → Secrets and variables → Actions
   - **Variables** タブ:
     - `AZURE_WEBAPP_NAME`: App Service の名前
     - `AZURE_RESOURCE_GROUP`: リソースグループ名
     - `AZURE_CLIENT_ID`: Service Principal のクライアント ID
     - `AZURE_TENANT_ID`: Azure AD テナント ID
     - `AZURE_SUBSCRIPTION_ID`: Azure サブスクリプション ID

## ライセンス

MIT License
