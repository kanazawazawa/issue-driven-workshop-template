# cleanup-participant.ps1
# Usage: ./cleanup-participant.ps1 -Number "02"
#
# Prerequisites:
#   - az login (Azure CLI)
#   - gh auth login (GitHub CLI)
#   - Copy config.json.template to config.json and fill in your values
#
# This script will:
#   1. Delete Azure Web App
#   2. Delete GitHub repository

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

# Azure Resources
$resourceGroup = $config.azure.resourceGroup
$webAppName = "$($config.azure.webAppNamePrefix)-$Number"

# GitHub
$ownerName = $config.github.owner
$repoName = "$($config.github.repoPrefix)-$Number"

# ===========================================
# Confirmation
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "WARNING: This will delete the following resources" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
Write-Host ""
Write-Host "Web App    : $webAppName" -ForegroundColor Yellow
Write-Host "Repository : $ownerName/$repoName" -ForegroundColor Yellow
Write-Host ""

$confirmation = Read-Host "Are you sure you want to continue? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

# ===========================================
# Step 1: Delete Azure Web App
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 1: Deleting Azure Web App" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Deleting Web App: $webAppName" -ForegroundColor Yellow
az webapp delete --name $webAppName --resource-group $resourceGroup

Write-Host "Web App deleted" -ForegroundColor Green

# ===========================================
# Step 2: Delete GitHub Repository
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 2: Deleting GitHub Repository" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Deleting repository: $ownerName/$repoName" -ForegroundColor Yellow
gh repo delete "$ownerName/$repoName" --yes

Write-Host "Repository deleted" -ForegroundColor Green

# ===========================================
# Summary
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Cleanup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Deleted Web App    : $webAppName" -ForegroundColor White
Write-Host "Deleted Repository : $ownerName/$repoName" -ForegroundColor White
Write-Host ""
