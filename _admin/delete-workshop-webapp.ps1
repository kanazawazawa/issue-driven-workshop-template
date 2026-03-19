# delete-workshop-webapp.ps1
# Usage: ./delete-workshop-webapp.ps1 -Number "01"
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
$webAppName = "$($config.azure.webAppNamePrefix)-$Number"

Write-Host "Deleting Web App: $webAppName" -ForegroundColor Red
az webapp delete --name $webAppName --resource-group $resourceGroup

Write-Host "Done!" -ForegroundColor Green
