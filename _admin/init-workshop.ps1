# init-workshop.ps1
# Usage: ./init-workshop.ps1 -ParticipantCount 5
#
# Prerequisites:
#   - az login (Azure CLI)
#   - gh auth login (GitHub CLI)
#
# This script will:
#   1. Create Azure resource group, App Service plan, and Storage account
#   2. Generate config.json automatically
#   3. Set up each participant's environment (Web App + repo + secrets + deploy)

param(
    [Parameter(Mandatory=$true)]
    [int]$ParticipantCount,

    [string]$Location = "japaneast",
    [string[]]$FallbackLocations = @("japanwest"),
    [string]$ResourceGroup = "",
    [string]$AppServicePlan = "",
    [string]$StorageAccount = "",
    [string]$WebAppNamePrefix = "",
    [string]$RepoOwner = "",
    [string]$TemplateRepoFullName = "",
    [string]$RepoNamePrefix = "",
    [string]$Visibility = "public",
    [string]$Sku = "P0v4"
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
# Validation
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Validating prerequisites" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check Azure CLI login
$azAccount = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Azure CLI is not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}
$subscriptionName = ($azAccount | ConvertFrom-Json).name
Write-Host "Azure subscription: $subscriptionName" -ForegroundColor Green

# Check GitHub CLI login
$ghStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: GitHub CLI is not logged in. Run 'gh auth login' first." -ForegroundColor Red
    exit 1
}
Write-Host "GitHub CLI: authenticated" -ForegroundColor Green

# Auto-detect template repo from the current repository's origin
if (-not $TemplateRepoFullName) {
    $originUrl = git remote get-url origin 2>$null
    if ($originUrl -and $originUrl -match '(?:github\.com|[^/:]+\.ghe\.com)[:/]([^/]+/[^/]+?)(?:\.git)?$') {
        $TemplateRepoFullName = $Matches[1]
    } else {
        Write-Host "ERROR: Could not detect template repo from git origin. Specify -TemplateRepoFullName." -ForegroundColor Red
        exit 1
    }
}
Write-Host "Template repo: $TemplateRepoFullName" -ForegroundColor Green

# Auto-detect target owner if not specified
if (-not $RepoOwner) {
    $RepoOwner = (gh api user --jq '.login') 2>$null
    if (-not $RepoOwner) {
        Write-Host "ERROR: Could not detect GitHub username. Specify -RepoOwner." -ForegroundColor Red
        exit 1
    }
}
Write-Host "Repo owner: $RepoOwner" -ForegroundColor Green

# Generate a shared random suffix for resource names (6 chars, lowercase alphanumeric)
$suffix = -join ((48..57) + (97..122) | Get-Random -Count 6 | ForEach-Object { [char]$_ })

if (-not $ResourceGroup)   { $ResourceGroup   = "rg-workshop-$suffix" }
if (-not $AppServicePlan)  { $AppServicePlan  = "plan-workshop-$suffix" }
if (-not $StorageAccount)  { $StorageAccount  = "saworkshop$suffix" }
if (-not $WebAppNamePrefix){ $WebAppNamePrefix = "app-workshop-$suffix" }
if (-not $RepoNamePrefix)  { $RepoNamePrefix  = "workshop-$suffix" }

# ===========================================
# Confirmation
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Workshop Setup Plan" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "Participants     : $ParticipantCount" -ForegroundColor White
Write-Host "Location         : $Location" -ForegroundColor White
Write-Host "Resource Group   : $ResourceGroup" -ForegroundColor White
Write-Host "App Service Plan : $AppServicePlan ($Sku)" -ForegroundColor White
Write-Host "Storage Account  : $StorageAccount" -ForegroundColor White
Write-Host "Web App Prefix   : $WebAppNamePrefix" -ForegroundColor White
Write-Host "Repo Owner       : $RepoOwner" -ForegroundColor White
Write-Host "Template Repo    : $TemplateRepoFullName" -ForegroundColor White
Write-Host "Repo Name Prefix : $RepoNamePrefix" -ForegroundColor White
Write-Host "Visibility       : $Visibility" -ForegroundColor White
Write-Host ""

$confirmation = Read-Host "Proceed? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Cancelled." -ForegroundColor Gray
    exit
}

# ===========================================
# Step 1: Create Azure Resources
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 1: Creating Azure Resources" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Invoke-AzCommand -Description "Creating resource group: $ResourceGroup" -Command {
    az group create --name $ResourceGroup --location $Location --output none
}

# Try App Service Plan creation with region fallback
$planLocations = @($Location) + $FallbackLocations
$planCreated = $false
$planLocation = $Location

foreach ($loc in $planLocations) {
    try {
        Invoke-AzCommand -Description "Creating App Service plan: $AppServicePlan ($Sku) in $loc" -Command {
            az appservice plan create --name $AppServicePlan --resource-group $ResourceGroup --location $loc --sku $Sku --output none
        }
        $planLocation = $loc
        $planCreated = $true
        Write-Host "App Service plan created in $loc" -ForegroundColor Green
        break
    }
    catch {
        Write-Host "Failed to create App Service plan in $loc : $_" -ForegroundColor Red
        if ($loc -ne $planLocations[-1]) {
            Write-Host "Trying next fallback location..." -ForegroundColor Yellow
        }
    }
}

if (-not $planCreated) {
    throw "Failed to create App Service plan in any location: $($planLocations -join ', ')"
}

Invoke-AzCommand -Description "Creating storage account: $StorageAccount" -Command {
    az storage account create --name $StorageAccount --resource-group $ResourceGroup --location $Location --sku Standard_LRS --output none
}

Write-Host "Azure resources created" -ForegroundColor Green

# ===========================================
# Step 2: Generate config.json
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 2: Generating config.json" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$config = @{
    azure = @{
        resourceGroup    = $ResourceGroup
        appServicePlan   = $AppServicePlan
        storageAccount   = $StorageAccount
        webAppNamePrefix = $WebAppNamePrefix
        tableNamePrefix  = "Expenses"
    }
    github = @{
        repoOwner            = $RepoOwner
        templateRepoFullName = $TemplateRepoFullName
        repoNamePrefix       = $RepoNamePrefix
        visibility   = $Visibility
    }
}

$configPath = Join-Path $PSScriptRoot "config.json"
$config | ConvertTo-Json -Depth 3 | Set-Content -Path $configPath -Encoding UTF8
Write-Host "config.json generated" -ForegroundColor Green

# ===========================================
# Step 3: Setup Each Participant
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 3: Setting Up Participants" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$setupScript = Join-Path $PSScriptRoot "setup-participant.ps1"
$results = @()

for ($i = 1; $i -le $ParticipantCount; $i++) {
    $number = $i.ToString("D2")
    Write-Host ""
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    Write-Host "Participant $number ($i/$ParticipantCount)" -ForegroundColor Cyan
    Write-Host "----------------------------------------" -ForegroundColor Cyan

    try {
        & $setupScript -Number $number
        $results += @{ Number = $number; Status = "OK" }
    }
    catch {
        Write-Host "ERROR: Failed to setup participant $number - $_" -ForegroundColor Red
        $results += @{ Number = $number; Status = "FAILED: $_" }
    }
}

# ===========================================
# Summary
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Workshop Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Azure Resources:" -ForegroundColor White
Write-Host "  Resource Group   : $ResourceGroup" -ForegroundColor White
Write-Host "  App Service Plan : $AppServicePlan" -ForegroundColor White
Write-Host "  Storage Account  : $StorageAccount" -ForegroundColor White
Write-Host ""
Write-Host "Participant Results:" -ForegroundColor White

foreach ($r in $results) {
    $color = if ($r.Status -eq "OK") { "Green" } else { "Red" }
    $webApp = "$WebAppNamePrefix-$($r.Number)"
    $repo = "$RepoOwner/$RepoNamePrefix-$($r.Number)"
    Write-Host "  [$($r.Status)] $($r.Number) - https://$webApp.azurewebsites.net | https://github.com/$repo" -ForegroundColor $color
}

Write-Host ""
Write-Host "Template Repo: https://github.com/$TemplateRepoFullName" -ForegroundColor White
Write-Host ""
