#############################################################################
# Cleanup Script for AKS OpenCost Demo
# 
# This script removes all Azure resources, Kubernetes resources, and
# local files created by the deployment scripts.
#############################################################################

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "AKS OpenCost Demo Cleanup" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

# ============================================================================
# CONFIGURATION
# ============================================================================
$RESOURCE_GROUP = "rg-opencost-demo"
$EXPORT_NAME = "opencost-daily"

# Get subscription ID
$SUBSCRIPTION_ID = az account show --query id -o tsv

Write-Host "`nThis will delete the following resources:" -ForegroundColor Yellow
Write-Host "  - Resource Group: $RESOURCE_GROUP (and all resources within)" -ForegroundColor White
Write-Host "  - Service Principal: OpenCostAccess" -ForegroundColor White
Write-Host "  - Custom Role: OpenCostRole" -ForegroundColor White
Write-Host "  - Cost Export: $EXPORT_NAME" -ForegroundColor White

$confirmation = Read-Host "`nAre you sure you want to proceed? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
    exit
}

# ============================================================================
# STEP 1: Delete Cost Export
# ============================================================================
Write-Host "`nStep 1: Deleting Cost Management Export..." -ForegroundColor Cyan

try {
    # Try using FinOps Toolkit if available
    if (Get-Module -ListAvailable -Name FinOpsToolkit) {
        Import-Module FinOpsToolkit
        Remove-FinOpsCostExport -Name $EXPORT_NAME -Scope "/subscriptions/$SUBSCRIPTION_ID" -RemoveData -ErrorAction SilentlyContinue
        Write-Host "Cost export deleted using FinOps Toolkit" -ForegroundColor Green
    } else {
        # Fall back to Azure CLI
        az costmanagement export delete --name $EXPORT_NAME --scope "subscriptions/$SUBSCRIPTION_ID" 2>$null
        Write-Host "Cost export deleted using Azure CLI" -ForegroundColor Green
    }
} catch {
    Write-Host "Cost export may not exist or already deleted" -ForegroundColor Gray
}

# ============================================================================
# STEP 2: Delete Service Principal
# ============================================================================
Write-Host "`nStep 2: Deleting Service Principal..." -ForegroundColor Cyan

$SP_ID = az ad sp list --display-name "OpenCostAccess" --query "[0].id" -o tsv 2>$null
if ($SP_ID) {
    az ad sp delete --id $SP_ID
    Write-Host "Service Principal deleted" -ForegroundColor Green
} else {
    Write-Host "Service Principal not found (may already be deleted)" -ForegroundColor Gray
}

# ============================================================================
# STEP 3: Delete Custom Role
# ============================================================================
Write-Host "`nStep 3: Deleting Custom Role..." -ForegroundColor Cyan

az role definition delete --name "OpenCostRole" 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "Custom role deleted" -ForegroundColor Green
} else {
    Write-Host "Custom role not found (may already be deleted)" -ForegroundColor Gray
}

# ============================================================================
# STEP 4: Delete Resource Group (includes AKS cluster and storage account)
# ============================================================================
Write-Host "`nStep 4: Deleting Resource Group (this may take several minutes)..." -ForegroundColor Cyan

az group delete --name $RESOURCE_GROUP --yes --no-wait
Write-Host "Resource group deletion initiated (running in background)" -ForegroundColor Green

# ============================================================================
# STEP 5: Clean up local files
# ============================================================================
Write-Host "`nStep 5: Cleaning up local files..." -ForegroundColor Cyan

$filesToDelete = @(
    "service-key.json",
    "cloud-integration.json",
    "opencost-role.json"
)

foreach ($file in $filesToDelete) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Host "  Deleted: $file" -ForegroundColor Gray
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Green
Write-Host "CLEANUP INITIATED!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green

Write-Host "`nDeleted:" -ForegroundColor Cyan
Write-Host "  ✓ Cost Management Export" -ForegroundColor White
Write-Host "  ✓ Service Principal (OpenCostAccess)" -ForegroundColor White
Write-Host "  ✓ Custom Role (OpenCostRole)" -ForegroundColor White
Write-Host "  ✓ Local credential files" -ForegroundColor White

Write-Host "`nIn Progress:" -ForegroundColor Yellow
Write-Host "  ⏳ Resource Group deletion (running in background)" -ForegroundColor White

Write-Host "`nTo check resource group deletion status:" -ForegroundColor Cyan
Write-Host "  az group show --name $RESOURCE_GROUP 2>&1" -ForegroundColor White

Write-Host "`nNote: The resource group deletion can take 5-10 minutes to complete." -ForegroundColor Gray
