# recover-workshop.ps1
# Usage: ./recover-workshop.ps1 -ParticipantCount 5
#
# Prerequisites:
#   - az login (Azure CLI)
#   - config.json must exist
#
# This script will:
#   1. Enable public network access on the Storage Account
#   2. Stop and start each participant's Web App (production + all deployment slots)
#   3. Verify site health

param(
    [Parameter(Mandatory=$true)]
    [int]$ParticipantCount
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
    Write-Host "Cannot determine resource names without config.json." -ForegroundColor Yellow
    exit 1
}

$config = Get-Content $configPath -Raw | ConvertFrom-Json

$resourceGroup = $config.azure.resourceGroup
$storageAccount = $config.azure.storageAccount
$webAppNamePrefix = $config.azure.webAppNamePrefix

# ===========================================
# Recovery Plan
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Workshop Recovery Plan" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Participants     : $ParticipantCount" -ForegroundColor White
Write-Host "Resource Group   : $resourceGroup" -ForegroundColor White
Write-Host "Storage Account  : $storageAccount" -ForegroundColor White
Write-Host "Web App Prefix   : $webAppNamePrefix" -ForegroundColor White
Write-Host ""

# ===========================================
# Step 1: Fix Storage Account network access
# ===========================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 1: Fixing Storage Account network access" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$currentAccess = (Invoke-AzCommand -Description "Checking current publicNetworkAccess" -Command {
    az storage account show --name $storageAccount --resource-group $resourceGroup --query publicNetworkAccess -o tsv
}) | Select-Object -Last 1

if ($currentAccess -eq "Enabled") {
    Write-Host "Public network access is already enabled — skipping" -ForegroundColor Green
} else {
    Invoke-AzCommand -Description "Enabling public network access on $storageAccount" -Command {
        az storage account update --name $storageAccount --resource-group $resourceGroup --public-network-access Enabled --output none
    }
    Write-Host "Public network access enabled" -ForegroundColor Green
}

# ===========================================
# Step 2: Restart Participant Environments
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 2: Restarting Participant Environments" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$results = @()

for ($i = 1; $i -le $ParticipantCount; $i++) {
    $number = $i.ToString("D2")
    $webAppName = "$webAppNamePrefix-$number"

    Write-Host ""
    Write-Host "--- Participant $number ---" -ForegroundColor Yellow

    # Restart production slot
    Write-Host "Stopping $webAppName (production)" -ForegroundColor Yellow
    az webapp stop --name $webAppName --resource-group $resourceGroup --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Web App not found or already stopped" -ForegroundColor Gray
        $results += @{ Number = $number; Status = "NOT FOUND" }
        continue
    }

    Start-Sleep -Seconds 3

    az webapp start --name $webAppName --resource-group $resourceGroup --output none
    Write-Host "  Production slot restarted" -ForegroundColor Green

    # Restart all deployment slots
    $slotsJson = az webapp deployment slot list --name $webAppName --resource-group $resourceGroup --query "[].name" -o json 2>$null
    $slots = @()
    if ($LASTEXITCODE -eq 0 -and $slotsJson) {
        $slots = ($slotsJson | Out-String).Trim() | ConvertFrom-Json
    }

    foreach ($slot in $slots) {
        Write-Host "  Stopping slot $slot" -ForegroundColor Yellow
        az webapp stop --name $webAppName --resource-group $resourceGroup --slot $slot --output none 2>$null
        Start-Sleep -Seconds 3
        az webapp start --name $webAppName --resource-group $resourceGroup --slot $slot --output none 2>$null
        Write-Host "  Slot $slot restarted" -ForegroundColor Green
    }

    $results += @{ Number = $number; Status = "OK"; Slots = $slots }
}

# ===========================================
# Step 3: Verify site health
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Step 3: Verifying site health" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Waiting for apps to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

foreach ($r in $results) {
    if ($r.Status -eq "NOT FOUND") { continue }

    $webAppName = "$webAppNamePrefix-$($r.Number)"

    # Check production
    $productionUrl = "https://$webAppName.azurewebsites.net"
    try {
        $response = Invoke-WebRequest -Uri $productionUrl -UseBasicParsing -TimeoutSec 30
        Write-Host "  $webAppName (production): $($response.StatusCode) OK" -ForegroundColor Green
    } catch {
        $status = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "unreachable" }
        Write-Host "  $webAppName (production): $status" -ForegroundColor Red
    }

    # Check slots
    foreach ($slot in $r.Slots) {
        $slotUrl = "https://$webAppName-$slot.azurewebsites.net"
        try {
            $response = Invoke-WebRequest -Uri $slotUrl -UseBasicParsing -TimeoutSec 30
            Write-Host "  $webAppName ($slot): $($response.StatusCode) OK" -ForegroundColor Green
        } catch {
            $status = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "unreachable" }
            Write-Host "  $webAppName ($slot): $status" -ForegroundColor Red
        }
    }
}

# ===========================================
# Summary
# ===========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Workshop Recovery Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

foreach ($r in $results) {
    $webAppName = "$webAppNamePrefix-$($r.Number)"
    $color = if ($r.Status -eq "OK") { "Green" } else { "Red" }
    $slotCount = if ($r.Slots) { $r.Slots.Count } else { 0 }
    Write-Host "  [$($r.Status)] $($r.Number) - https://$webAppName.azurewebsites.net (slots: $slotCount)" -ForegroundColor $color
}

Write-Host ""
