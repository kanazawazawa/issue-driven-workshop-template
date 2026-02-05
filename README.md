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

テンプレートファイルをコピーして、接続文字列を設定してください。

```bash
cp appsettings.Development.json.template appsettings.Development.json
```

`appsettings.Development.json` を編集し、Azure Table Storage の接続文字列を設定：

```json
{
  "AzureTableStorage": {
    "ConnectionString": "<YOUR_CONNECTION_STRING>",
    "TableName": "Expenses"
  }
}
```

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

`main` ブランチへの Pull Request 作成時、または手動トリガーで Azure App Service にデプロイされます。

### セットアップ手順

1. **Azure App Service を作成**
2. **発行プロファイルを取得**: Azure Portal → App Service → 発行プロファイルのダウンロード
3. **GitHub に登録**: リポジトリ → Settings → Secrets and variables → Actions
   - **Variables** タブ:
     - `AZURE_WEBAPP_NAME`: App Service の名前
   - **Secrets** タブ:
     - `AZURE_WEBAPP_PUBLISH_PROFILE`: 発行プロファイルの内容

## ライセンス

MIT License
