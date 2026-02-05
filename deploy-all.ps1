#############################################################################
# Complete OpenCost on AKS Deployment - Single Command
# 
# This script runs the complete deployment in one go:
# 1. Creates AKS cluster with Prometheus and OpenCost
# 2. Configures Azure Cloud Costs integration
# 3. Verifies the deployment
#
# Usage:
#   .\deploy-all.ps1                    # Full deployment with login
#   .\deploy-all.ps1 -SkipLogin         # Skip Azure login (already logged in)
#   .\deploy-all.ps1 -SkipCloudCosts    # Skip cloud costs integration
#
# Prerequisites:
# - Azure CLI installed
# - Helm installed
# - kubectl installed
# - PowerShell 7+
#############################################################################

param(
    [switch]$SkipLogin,
    [switch]$SkipCloudCosts,
    [switch]$SkipVerification,
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost on AKS - Complete Deployment" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will:" -ForegroundColor White
Write-Host "  1. Create an AKS cluster" -ForegroundColor Gray
Write-Host "  2. Install Prometheus for metrics" -ForegroundColor Gray
Write-Host "  3. Install OpenCost for cost monitoring" -ForegroundColor Gray
if (-not $SkipCloudCosts) {
    Write-Host "  4. Configure Azure Cloud Costs integration" -ForegroundColor Gray
    Write-Host "  5. Verify the deployment" -ForegroundColor Gray
} else {
    Write-Host "  4. Verify the deployment" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Estimated time: 15-20 minutes" -ForegroundColor Yellow
Write-Host ""

$confirmation = Read-Host "Continue? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit
}

# ============================================================================
# STEP 1: Deploy AKS + OpenCost
# ============================================================================
Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host " PHASE 1: Deploying AKS Cluster + OpenCost" -ForegroundColor Magenta
Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Magenta

$deployParams = @()
if ($SkipLogin) { $deployParams += "-SkipLogin" }
if ($SubscriptionId) { $deployParams += "-SubscriptionId", $SubscriptionId }

$deployScript = Join-Path $scriptPath "deploy-aks-opencost.ps1"
& $deployScript @deployParams

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n✗ AKS deployment failed!" -ForegroundColor Red
    exit 1
}

# ============================================================================
# STEP 2: Configure Azure Cloud Costs
# ============================================================================
if (-not $SkipCloudCosts) {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host " PHASE 2: Configuring Azure Cloud Costs Integration" -ForegroundColor Magenta
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Magenta

    $cloudCostsScript = Join-Path $scriptPath "setup-azure-cloud-costs.ps1"
    & $cloudCostsScript -SkipPrerequisiteCheck

    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n⚠ Cloud costs setup had issues, but OpenCost is still functional" -ForegroundColor Yellow
    }
}

# ============================================================================
# STEP 3: Verify Deployment
# ============================================================================
if (-not $SkipVerification) {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host " PHASE 3: Verifying Deployment" -ForegroundColor Magenta
    Write-Host "═══════════════════════════════════════════════════════════════════════════" -ForegroundColor Magenta

    Start-Sleep -Seconds 30  # Wait for pods to stabilize
    
    $verifyScript = Join-Path $scriptPath "verify-deployment.ps1"
    & $verifyScript
}

# ============================================================================
# COMPLETE
# ============================================================================
Write-Host "`n" -NoNewline
Write-Host "╔═══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                     DEPLOYMENT COMPLETE!                                   ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Green

$OPENCOST_IP = kubectl get service opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

Write-Host ""
Write-Host "What was deployed:" -ForegroundColor Cyan
Write-Host "  ✓ AKS Cluster: aks-opencost-demo" -ForegroundColor White
Write-Host "  ✓ Prometheus: Metrics collection" -ForegroundColor White
Write-Host "  ✓ OpenCost: Cost monitoring" -ForegroundColor White
if (-not $SkipCloudCosts) {
    Write-Host "  ✓ Azure Cloud Costs: Billing integration" -ForegroundColor White
}

if ($OPENCOST_IP) {
    Write-Host ""
    Write-Host "Access OpenCost:" -ForegroundColor Cyan
    Write-Host "  UI:  http://$OPENCOST_IP`:9090" -ForegroundColor White
    Write-Host "  API: http://$OPENCOST_IP`:9090/model/allocation?window=1h&aggregate=namespace" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Open in browser:" -ForegroundColor Yellow
    Write-Host "  Start-Process `"http://$OPENCOST_IP`:9090`"" -ForegroundColor White
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  - View the OpenCost UI to see Kubernetes costs" -ForegroundColor Gray
Write-Host "  - Navigate to 'Cloud Costs' to see Azure billing data" -ForegroundColor Gray
Write-Host "  - Run .\generate-load.ps1 to deploy sample applications" -ForegroundColor Gray
Write-Host "  - Run .\cleanup.ps1 when done to delete all resources" -ForegroundColor Gray
