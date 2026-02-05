#############################################################################
# Verification Script for OpenCost Deployment
# 
# This script verifies that OpenCost is properly deployed and 
# Azure Cloud Costs integration is working.
#############################################################################

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost Deployment Verification" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

$allPassed = $true

# ============================================================================
# CHECK 1: Kubernetes Connectivity
# ============================================================================
Write-Host "`n[CHECK 1] Kubernetes Connectivity" -ForegroundColor Yellow

try {
    $nodes = kubectl get nodes -o json 2>$null | ConvertFrom-Json
    if ($nodes.items.Count -gt 0) {
        Write-Host "  ✓ Connected to cluster with $($nodes.items.Count) nodes" -ForegroundColor Green
    } else {
        Write-Host "  ✗ No nodes found" -ForegroundColor Red
        $allPassed = $false
    }
} catch {
    Write-Host "  ✗ Cannot connect to Kubernetes cluster" -ForegroundColor Red
    $allPassed = $false
}

# ============================================================================
# CHECK 2: Prometheus Deployment
# ============================================================================
Write-Host "`n[CHECK 2] Prometheus Deployment" -ForegroundColor Yellow

$promPods = kubectl get pods -n prometheus-system -l app.kubernetes.io/name=prometheus -o json 2>$null | ConvertFrom-Json
if ($promPods.items.Count -gt 0 -and $promPods.items[0].status.phase -eq "Running") {
    Write-Host "  ✓ Prometheus is running" -ForegroundColor Green
} else {
    Write-Host "  ✗ Prometheus is not running" -ForegroundColor Red
    $allPassed = $false
}

# ============================================================================
# CHECK 3: OpenCost Deployment
# ============================================================================
Write-Host "`n[CHECK 3] OpenCost Deployment" -ForegroundColor Yellow

$opencostPods = kubectl get pods -n opencost -l app.kubernetes.io/name=opencost -o json 2>$null | ConvertFrom-Json
if ($opencostPods.items.Count -gt 0 -and $opencostPods.items[0].status.phase -eq "Running") {
    Write-Host "  ✓ OpenCost is running" -ForegroundColor Green
} else {
    Write-Host "  ✗ OpenCost is not running" -ForegroundColor Red
    $allPassed = $false
}

# ============================================================================
# CHECK 4: OpenCost Service
# ============================================================================
Write-Host "`n[CHECK 4] OpenCost LoadBalancer Service" -ForegroundColor Yellow

$OPENCOST_IP = kubectl get service opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
if ($OPENCOST_IP) {
    Write-Host "  ✓ LoadBalancer IP: $OPENCOST_IP" -ForegroundColor Green
} else {
    Write-Host "  ⚠ LoadBalancer IP not yet assigned (may still be provisioning)" -ForegroundColor Yellow
}

# ============================================================================
# CHECK 5: Azure Service Key Secret
# ============================================================================
Write-Host "`n[CHECK 5] Azure Service Key Secret" -ForegroundColor Yellow

$serviceKeySecret = kubectl get secret azure-service-key -n opencost -o json 2>$null | ConvertFrom-Json
if ($serviceKeySecret) {
    Write-Host "  ✓ azure-service-key secret exists" -ForegroundColor Green
} else {
    Write-Host "  ✗ azure-service-key secret not found" -ForegroundColor Red
    $allPassed = $false
}

# ============================================================================
# CHECK 6: Cloud Costs Secret
# ============================================================================
Write-Host "`n[CHECK 6] Cloud Costs Secret" -ForegroundColor Yellow

$cloudCostsSecret = kubectl get secret cloud-costs -n opencost -o json 2>$null | ConvertFrom-Json
if ($cloudCostsSecret) {
    Write-Host "  ✓ cloud-costs secret exists" -ForegroundColor Green
    
    # Decode and check content
    $cloudIntegrationB64 = $cloudCostsSecret.data.'cloud-integration.json'
    if ($cloudIntegrationB64) {
        $cloudIntegration = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($cloudIntegrationB64)) | ConvertFrom-Json
        if ($cloudIntegration.azure.storage[0].path) {
            Write-Host "  ✓ Export path configured: $($cloudIntegration.azure.storage[0].path)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Export path is empty (may cause issues)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ⚠ cloud-costs secret not found (cloud costs integration not configured)" -ForegroundColor Yellow
}

# ============================================================================
# CHECK 7: OpenCost Health
# ============================================================================
Write-Host "`n[CHECK 7] OpenCost Health Check" -ForegroundColor Yellow

if ($OPENCOST_IP) {
    try {
        $healthResponse = Invoke-RestMethod -Uri "http://$OPENCOST_IP`:9090/healthz" -TimeoutSec 5 2>$null
        Write-Host "  ✓ Health check passed" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠ Health check failed (service may still be starting)" -ForegroundColor Yellow
    }
}

# ============================================================================
# CHECK 8: OpenCost Allocation API
# ============================================================================
Write-Host "`n[CHECK 8] OpenCost Allocation API" -ForegroundColor Yellow

if ($OPENCOST_IP) {
    try {
        $allocationResponse = Invoke-RestMethod -Uri "http://$OPENCOST_IP`:9090/model/allocation?window=1h&aggregate=namespace" -TimeoutSec 10 2>$null
        if ($allocationResponse.code -eq 200) {
            Write-Host "  ✓ Allocation API responding" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Allocation API returned code: $($allocationResponse.code)" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  ⚠ Allocation API not responding (may need more time to collect data)" -ForegroundColor Yellow
    }
}

# ============================================================================
# CHECK 9: Cloud Costs Ingestion
# ============================================================================
Write-Host "`n[CHECK 9] Cloud Costs Ingestion" -ForegroundColor Yellow

$logs = kubectl logs deployment/opencost -n opencost -c opencost --tail=100 2>$null
if ($logs -match "retrieved.*csv.*size") {
    Write-Host "  ✓ Cloud cost data has been ingested" -ForegroundColor Green
    $logs -split "`n" | Where-Object { $_ -match "retrieved.*csv" } | Select-Object -First 2 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor Gray
    }
} elseif ($logs -match "ingestor.*completed") {
    Write-Host "  ✓ Ingestor has run" -ForegroundColor Green
} else {
    Write-Host "  ⚠ No cloud cost ingestion detected yet (export may still be running)" -ForegroundColor Yellow
}

# Check for errors
if ($logs -match "error|Error|ERR") {
    Write-Host "`n  Recent errors in logs:" -ForegroundColor Yellow
    $logs -split "`n" | Where-Object { $_ -match "error|Error|ERR" } | Select-Object -First 3 | ForEach-Object {
        Write-Host "    $_" -ForegroundColor Gray
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "ALL CRITICAL CHECKS PASSED" -ForegroundColor Green
} else {
    Write-Host "SOME CHECKS FAILED - Review the output above" -ForegroundColor Red
}
Write-Host "============================================================================" -ForegroundColor Cyan

if ($OPENCOST_IP) {
    Write-Host "`nOpenCost UI: http://$OPENCOST_IP`:9090" -ForegroundColor White
    Write-Host "`nUseful Commands:" -ForegroundColor Cyan
    Write-Host "  # View live logs" -ForegroundColor Gray
    Write-Host "  kubectl logs deployment/opencost -n opencost -c opencost -f" -ForegroundColor White
    Write-Host "`n  # Query cloud costs API" -ForegroundColor Gray
    Write-Host "  curl `"http://$OPENCOST_IP`:9090/model/cloudCost?window=7d&aggregate=service`"" -ForegroundColor White
}
