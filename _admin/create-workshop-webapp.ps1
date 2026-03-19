# create-workshop-webapp.ps1
# Usage: ./create-workshop-webapp.ps1 -Number "01"
#
# Prerequisites:
#   - az login (Azure CLI)
#   - Copy config.json.template to config.json and fill in your values

param(
    [Parameter(Mandatory=$true)]
    [string]$Number
)

# ===========================================
# Load Configuration
# ===========================================
$configPath = Join-Path $PSScriptRoot "config.json"
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: config.json not found." -ForegroundColor Red
    Write-Host "Copy config.json.template to config.json and fill in your values." -ForegroundColor Yellow
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

$resourceGroup = $config.azure.resourceGroup
$appServicePlan = $config.azure.appServicePlan
$webAppName = "$($config.azure.webAppNamePrefix)-$Number"
$connectionString = $config.azure.connectionString
$tableName = "$($config.azure.tableNamePrefix)$Number"

Write-Host "Creating Web App: $webAppName" -ForegroundColor Cyan
az webapp create --name $webAppName --resource-group $resourceGroup --plan $appServicePlan --runtime "dotnet:8" --tags "CostControl=Ignore" "SecurityControl=Ignore" --basic-auth Enabled

Write-Host "Configuring App Settings..." -ForegroundColor Cyan
az webapp config appsettings set --name $webAppName --resource-group $resourceGroup --settings "AzureTableStorage__ConnectionString=$connectionString" "AzureTableStorage__TableName=$tableName" --output none

Write-Host "Configuring 64-bit platform..." -ForegroundColor Cyan
az webapp config set --name $webAppName --resource-group $resourceGroup --use-32bit-worker-process false --output none

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
Write-Host "URL: https://$webAppName.azurewebsites.net" -ForegroundColor Yellow
