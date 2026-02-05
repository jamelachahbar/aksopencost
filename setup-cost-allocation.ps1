#############################################################################
# OpenCost Cost Allocation Configuration (Real Azure Pricing)
#
# This script sets up cost allocation rules for OpenCost WITHOUT overriding
# real Azure pricing. It only configures:
# - Label-based cost attribution
# - Shared cost distribution queries
#
# Real Azure pricing is preserved from the RateCard API.
#
# Usage:
#   .\setup-cost-allocation.ps1                    # Apply labels to workloads
#############################################################################

param(
    # Labels to apply to sample workloads
    [string]$Team = "demo",
    [string]$Project = "sample-app",
    [string]$Environment = "dev",
    [string]$CostCenter = "CC-1001"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost Cost Allocation Setup (Real Azure Pricing)" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  NOTE: Real Azure pricing from RateCard API is preserved." -ForegroundColor Green
Write-Host "  This script only configures cost ATTRIBUTION via labels." -ForegroundColor Gray

# ============================================================================
# Step 1: Apply Labels to Sample Workloads (Deployment Templates)
# ============================================================================
Write-Host "`nStep 1: Applying cost allocation labels to deployments..." -ForegroundColor Yellow

# Get all deployments in sample-app namespace
$deployments = kubectl get deployments -n sample-app -o jsonpath='{.items[*].metadata.name}' 2>$null

if ($deployments) {
    foreach ($deployment in $deployments.Split(' ')) {
        if ($deployment -and $deployment -ne "load-generator" -and $deployment -ne "stress-test") {
            Write-Host "  Patching deployment: $deployment" -ForegroundColor Gray
            
            # Patch the pod template labels (so new pods get the labels)
            kubectl patch deployment $deployment -n sample-app --type='json' `
                -p="[{`"op`": `"add`", `"path`": `"/spec/template/metadata/labels/team`", `"value`": `"$Team`"}]" 2>$null | Out-Null
            kubectl patch deployment $deployment -n sample-app --type='json' `
                -p="[{`"op`": `"add`", `"path`": `"/spec/template/metadata/labels/project`", `"value`": `"$Project`"}]" 2>$null | Out-Null
            kubectl patch deployment $deployment -n sample-app --type='json' `
                -p="[{`"op`": `"add`", `"path`": `"/spec/template/metadata/labels/environment`", `"value`": `"$Environment`"}]" 2>$null | Out-Null
            kubectl patch deployment $deployment -n sample-app --type='json' `
                -p="[{`"op`": `"add`", `"path`": `"/spec/template/metadata/labels/cost-center`", `"value`": `"$CostCenter`"}]" 2>$null | Out-Null
            
            Write-Host "  ✓ Labeled deployment: $deployment" -ForegroundColor Green
        }
    }
    
    # Restart deployments to apply labels to running pods
    Write-Host "`n  Restarting deployments to apply labels to pods..." -ForegroundColor Gray
    kubectl rollout restart deployment/nginx-sample deployment/redis-sample -n sample-app 2>$null | Out-Null
    kubectl rollout status deployment/nginx-sample -n sample-app --timeout=60s 2>$null | Out-Null
    Write-Host "  ✓ Deployments restarted with new labels" -ForegroundColor Green
} else {
    Write-Host "  No deployments found in sample-app namespace" -ForegroundColor Gray
}

# Verify labels were applied
Write-Host "`n  Verifying pod labels..." -ForegroundColor Gray
$podLabels = kubectl get pods -n sample-app -l app=nginx-sample -o jsonpath='{.items[0].metadata.labels.cost-center}' 2>$null
if ($podLabels -eq $CostCenter) {
    Write-Host "  ✓ Pods have cost-center=$CostCenter label" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Labels may take a moment to propagate" -ForegroundColor Yellow
}

# ============================================================================
# Step 2: Display Example Queries
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "Cost Allocation Labels Applied!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Cyan

$OPENCOST_IP = kubectl get svc opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

Write-Host "`nLabels Applied:" -ForegroundColor Yellow
Write-Host "  team=$Team" -ForegroundColor White
Write-Host "  project=$Project" -ForegroundColor White
Write-Host "  environment=$Environment" -ForegroundColor White
Write-Host "  cost-center=$CostCenter" -ForegroundColor White

Write-Host "`nExample Queries (using REAL Azure pricing):" -ForegroundColor Yellow
Write-Host ""
Write-Host "  # By Namespace" -ForegroundColor Gray
Write-Host "  curl `"http://${OPENCOST_IP}:9090/model/allocation?window=7d&aggregate=namespace`"" -ForegroundColor White
Write-Host ""
Write-Host "  # By Team Label" -ForegroundColor Gray
Write-Host "  curl `"http://${OPENCOST_IP}:9090/model/allocation?window=7d&aggregate=label:team`"" -ForegroundColor White
Write-Host ""
Write-Host "  # By Cost Center" -ForegroundColor Gray
Write-Host "  curl `"http://${OPENCOST_IP}:9090/model/allocation?window=7d&aggregate=label:cost-center`"" -ForegroundColor White
Write-Host ""
Write-Host "  # With Shared/Idle Costs Distributed" -ForegroundColor Gray
Write-Host "  curl `"http://${OPENCOST_IP}:9090/model/allocation?window=7d&aggregate=namespace&shareIdle=true&shareNamespaces=kube-system&shareSplit=weighted`"" -ForegroundColor White
Write-Host ""
Write-Host "  # Multi-level (team + project)" -ForegroundColor Gray
Write-Host "  curl `"http://${OPENCOST_IP}:9090/model/allocation?window=7d&aggregate=label:team,label:project`"" -ForegroundColor White

Write-Host "`nTo label other workloads:" -ForegroundColor Yellow
Write-Host "  kubectl label deployment <name> -n <namespace> team=<team> project=<project> cost-center=<CC-XXXX>" -ForegroundColor Cyan

Write-Host "`nOpenCost UI: http://${OPENCOST_IP}:9090" -ForegroundColor Green
