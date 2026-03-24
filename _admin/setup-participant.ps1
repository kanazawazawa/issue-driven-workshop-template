# setup-participant.ps1
# Usage: ./setup-participant.ps1 -Number "01"
# 
# Prerequisites:
#   - az login (Azure CLI)
#   - gh auth login (GitHub CLI)
#   - Copy config.json.template to config.json and fill in your values
#
# This script will:
#   1. Create Azure Web App
#   2. Configure app settings
#   3. Create repository from template
#   4. Set GitHub Actions secrets
#   5. Trigger initial deployment

param(
    [Parameter(Mandatory=$true)]
    [string]$Number
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ===========================================
# Helper: Run az CLI with exit code checking
# ===========================================
function Invoke-AzCommand {
    param([string]$Description, [scriptblock]$Command)
    Write-Host "$Description" -ForegroundColor Yellow
    $output = & $Command 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errorMsg = ($output | Out-String).Trim()
        throw "az command failed: $Description`n$errorMsg"
    }
    return $output
}

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
$appServicePlan = $config.azure.appServicePlan
$webAppName = "$($config.azure.webAppNamePrefix)-$Number"
$storageAccount = $config.azure.storageAccount

# OIDC (for PR preview environments)
$clientId = $config.oidc.clientId
$tenantId = $config.oidc.tenantId
$subscriptionId = $config.oidc.subscriptionId

# App Settings
$tableName = "$($config.azure.tableNamePrefix)$Number"

# GitHub
$templateRepoFullName = $config.github.templateRepoFullName
$templateBranch = if ($config.github.templateBranch) { $config.github.templateBranch } else { "" }
$newRepoName = "$($config.github.repoNamePrefix)-$Number"
$repoOwner = $config.github.repoOwner
$visibility = if ($config.github.visibility) { "--$($config.github.visibility)" } else { "--public" }

# ===========================================
# Step 1: Create Azure Web App
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 1: Creating Azure Web App" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Invoke-AzCommand -Description "Creating Web App: $webAppName" -Command {
    az webapp create --name $webAppName --resource-group $resourceGroup --plan $appServicePlan --runtime "dotnet:8" --tags "CostControl=Ignore" "SecurityControl=Ignore" --basic-auth Enabled
} | Out-Null

# ===========================================
# Step 2: Configure App Settings & Managed Identity
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 2: Configuring App Settings & Managed Identity" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Invoke-AzCommand -Description "Configuring app settings" -Command {
    az webapp config appsettings set --name $webAppName --resource-group $resourceGroup --settings "AzureTableStorage__StorageAccountName=$storageAccount" "AzureTableStorage__TableName=$tableName" --output none
}

Invoke-AzCommand -Description "Configuring 64-bit platform" -Command {
    az webapp config set --name $webAppName --resource-group $resourceGroup --use-32bit-worker-process false --output none
}

$principalId = (Invoke-AzCommand -Description "Enabling Managed Identity" -Command {
    az webapp identity assign --name $webAppName --resource-group $resourceGroup --query principalId -o tsv
}) | Select-Object -Last 1

$storageId = (Invoke-AzCommand -Description "Getting storage account ID" -Command {
    az storage account show --name $storageAccount --resource-group $resourceGroup --query id -o tsv
}) | Select-Object -Last 1

Invoke-AzCommand -Description "Assigning role" -Command {
    az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role "Storage Table Data Contributor" --scope $storageId --output none
}

Write-Host "App settings and Managed Identity configured" -ForegroundColor Green

# ===========================================
# Step 3: Create Repository & Configure Variables
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 3: Creating Repository from Template" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Creating repository: $repoOwner/$newRepoName" -ForegroundColor Yellow

if ($templateBranch) {
    # Create empty repo first
    gh repo create "$repoOwner/$newRepoName" $visibility --clone=false
    Write-Host "Cloning template branch '$templateBranch'..." -ForegroundColor Yellow

    $cloneDir = Join-Path $env:TEMP "workshop-clone-$newRepoName-$(Get-Random)"
    $pushDir = Join-Path $env:TEMP "workshop-push-$newRepoName-$(Get-Random)"

    git clone --branch $templateBranch --single-branch "https://github.com/$templateRepoFullName.git" $cloneDir

    # Copy all files except _admin and .git to a fresh repo
    New-Item -ItemType Directory -Path $pushDir | Out-Null
    Get-ChildItem -Path $cloneDir -Force | Where-Object { $_.Name -notin @('.git', '_admin') } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $pushDir -Recurse -Force
    }

    Push-Location $pushDir
    git init --quiet
    git add -A
    git commit -m "Initial commit from template ($templateBranch)" --quiet
    git remote add origin "https://github.com/$repoOwner/$newRepoName.git"
    git branch -M main
    # Do NOT push yet — set variables and credentials first so the push-triggered workflow can use them
    Pop-Location

    Remove-Item $cloneDir -Recurse -Force

    # --- Set variables and credentials BEFORE push ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Step 4: Setting GitHub Variables & OIDC Credential" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "Setting AZURE_WEBAPP_NAME (as variable)..." -ForegroundColor Yellow
    gh variable set AZURE_WEBAPP_NAME --body $webAppName --repo "$repoOwner/$newRepoName"

    Write-Host "Setting OIDC variables..." -ForegroundColor Yellow
    gh variable set AZURE_RESOURCE_GROUP --body $resourceGroup --repo "$repoOwner/$newRepoName"
    gh variable set AZURE_CLIENT_ID --body $clientId --repo "$repoOwner/$newRepoName"
    gh variable set AZURE_TENANT_ID --body $tenantId --repo "$repoOwner/$newRepoName"
    gh variable set AZURE_SUBSCRIPTION_ID --body $subscriptionId --repo "$repoOwner/$newRepoName"

    Write-Host "Adding OIDC federated credential for $repoOwner/$newRepoName main branch..." -ForegroundColor Yellow
    $appObjectId = az ad app show --id $clientId --query id -o tsv
    $credentialFile = Join-Path $env:TEMP "oidc-main-$newRepoName.json"
    @{
        name = "github-main-$newRepoName"
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:$repoOwner/$($newRepoName):ref:refs/heads/main"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json | Set-Content -Path $credentialFile -Encoding utf8

    az ad app federated-credential create --id $appObjectId --parameters "@$credentialFile" --output none
    Remove-Item $credentialFile -ErrorAction SilentlyContinue
    Write-Host "OIDC federated credential configured" -ForegroundColor Green

    # --- Now push to trigger deployment ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Step 5: Pushing to Repository (triggers deployment)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Push-Location $pushDir
    git push -u origin main
    Pop-Location
    Remove-Item $pushDir -Recurse -Force
    Write-Host "Push complete — deployment triggered via push event" -ForegroundColor Green
} else {
    gh repo create "$repoOwner/$newRepoName" --template "$templateRepoFullName" $visibility --clone=false

    # Wait for repository to be ready
    Write-Host "Waiting for repository to be ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5

    # --- Remove _admin folder ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Step 4: Removing _admin folder from participant repo" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $repoFullName = "$repoOwner/$newRepoName"
    $cloneDir = Join-Path $env:TEMP "workshop-cleanup-clone-$newRepoName-$(Get-Random)"
    $pushDir = Join-Path $env:TEMP "workshop-cleanup-push-$newRepoName-$(Get-Random)"

    git clone --depth 1 "https://github.com/$repoFullName.git" $cloneDir 2>$null

    if (Test-Path (Join-Path $cloneDir "_admin")) {
        New-Item -ItemType Directory -Path $pushDir | Out-Null
        Get-ChildItem -Path $cloneDir -Force | Where-Object { $_.Name -notin @('.git', '_admin') } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $pushDir -Recurse -Force
        }

        Push-Location $pushDir
        git init --quiet
        git add -A
        git commit -m "Initial commit from template" --quiet
        git remote add origin "https://github.com/$repoFullName.git"
        git branch -M main
        git push -u origin main --force
        Pop-Location

        Remove-Item $pushDir -Recurse -Force
        Write-Host "_admin folder excluded from participant repo" -ForegroundColor Green
    } else {
        Write-Host "_admin folder not found, skipping" -ForegroundColor Gray
    }
    Remove-Item $cloneDir -Recurse -Force

    # --- Set variables and credentials ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Step 5: Setting GitHub Variables & OIDC Credential" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "Setting AZURE_WEBAPP_NAME (as variable)..." -ForegroundColor Yellow
    gh variable set AZURE_WEBAPP_NAME --body $webAppName --repo "$repoOwner/$newRepoName"

    Write-Host "Setting OIDC variables..." -ForegroundColor Yellow
    gh variable set AZURE_RESOURCE_GROUP --body $resourceGroup --repo "$repoOwner/$newRepoName"
    gh variable set AZURE_CLIENT_ID --body $clientId --repo "$repoOwner/$newRepoName"
    gh variable set AZURE_TENANT_ID --body $tenantId --repo "$repoOwner/$newRepoName"
    gh variable set AZURE_SUBSCRIPTION_ID --body $subscriptionId --repo "$repoOwner/$newRepoName"

    Write-Host "Adding OIDC federated credential for $repoOwner/$newRepoName main branch..." -ForegroundColor Yellow
    $appObjectId = az ad app show --id $clientId --query id -o tsv
    $credentialFile = Join-Path $env:TEMP "oidc-main-$newRepoName.json"
    @{
        name = "github-main-$newRepoName"
        issuer = "https://token.actions.githubusercontent.com"
        subject = "repo:$repoOwner/$($newRepoName):ref:refs/heads/main"
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json | Set-Content -Path $credentialFile -Encoding utf8

    az ad app federated-credential create --id $appObjectId --parameters "@$credentialFile" --output none
    Remove-Item $credentialFile -ErrorAction SilentlyContinue
    Write-Host "OIDC federated credential configured" -ForegroundColor Green

    # --- Trigger deployment ---
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Step 6: Triggering Initial Deployment" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    Write-Host "Waiting for repository to be fully ready..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10

    Write-Host "Triggering deployment workflow..." -ForegroundColor Yellow
    gh workflow run deploy.yml --repo "$repoOwner/$newRepoName"
    Write-Host "Deployment triggered" -ForegroundColor Green
}

# ===========================================
# Summary
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Web App URL  : https://$webAppName.azurewebsites.net" -ForegroundColor White
Write-Host "Repository   : https://github.com/$repoOwner/$newRepoName" -ForegroundColor White
Write-Host "Table Name   : $tableName" -ForegroundColor White
Write-Host "Deployment   : Triggered (check Actions tab for status)" -ForegroundColor White
Write-Host ""
