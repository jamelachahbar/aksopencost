#############################################################################
# Azure Cloud Costs Integration for OpenCost
# 
# This script sets up Azure Cost Management Export using FinOps Toolkit
# and configures OpenCost to read Azure billing data from Azure Storage.
#
# Prerequisites:
# - Azure CLI installed and logged in
# - OpenCost already deployed on AKS (run deploy-aks-opencost.ps1 first)
# - Helm installed
# - PowerShell 7+
#
# Azure Cost Export Requirements:
# - Dataset Type: ActualCost (required for accurate billing data)
# - Export Format: CSV (OpenCost reads CSV files)
# - Schedule: Daily (recommended for up-to-date costs)
# - Storage: Azure Blob Storage with hierarchical namespace (Data Lake Gen2)
#
# Key Features:
# - Uses FinOps Toolkit for proper export structure
# - Handles Azure Policy bypass for shared key access
# - Includes emptyDir volume fix for cloud cost database
# - Supports AZURE_CLIENT_ID for managed identity
#############################################################################

param(
    [switch]$SkipPrerequisiteCheck
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Azure Cloud Costs Integration Setup for OpenCost" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================
if (-not $SkipPrerequisiteCheck) {
    Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow
    
    # Check Azure CLI login
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Host "  ✗ Not logged in to Azure. Run 'az login' first." -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ Azure CLI logged in as: $($account.user.name)" -ForegroundColor Green
    
    # Check kubectl connection
    $nodes = kubectl get nodes -o json 2>$null | ConvertFrom-Json
    if (-not $nodes -or $nodes.items.Count -eq 0) {
        Write-Host "  ✗ Cannot connect to Kubernetes cluster. Run deploy-aks-opencost.ps1 first." -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ Connected to Kubernetes cluster with $($nodes.items.Count) nodes" -ForegroundColor Green
    
    # Check OpenCost deployment
    $opencostPod = kubectl get pods -n opencost -l app.kubernetes.io/name=opencost -o json 2>$null | ConvertFrom-Json
    if (-not $opencostPod -or $opencostPod.items.Count -eq 0) {
        Write-Host "  ✗ OpenCost not deployed. Run deploy-aks-opencost.ps1 first." -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ OpenCost is deployed" -ForegroundColor Green
    
    # Check Helm
    $helmVersion = helm version --short 2>$null
    if (-not $helmVersion) {
        Write-Host "  ✗ Helm not found. Install from: https://helm.sh/docs/intro/install/" -ForegroundColor Red
        exit 1
    }
    Write-Host "  ✓ Helm version: $helmVersion" -ForegroundColor Green
    
    Write-Host "`nAll prerequisites met!" -ForegroundColor Green
}

# ============================================================================
# CONFIGURATION
# ============================================================================
$RESOURCE_GROUP = "rg-opencost-demo"
$LOCATION = "swedencentral"
$CLUSTER_NAME = "aks-opencost-demo"
$STORAGE_ACCOUNT_NAME = "opencostexport$(Get-Random -Maximum 9999)"  # Must be globally unique
$CONTAINER_NAME = "cost-exports"
$EXPORT_NAME = "opencost-daily"

# Get subscription ID
$SUBSCRIPTION_ID = az account show --query id -o tsv
Write-Host "`nUsing Subscription: $SUBSCRIPTION_ID" -ForegroundColor Green

# ============================================================================
# STEP 1: Install FinOps Toolkit Module
# ============================================================================
Write-Host "`nStep 1: Installing/Importing FinOps Toolkit module..." -ForegroundColor Cyan

if (!(Get-Module -ListAvailable -Name FinOpsToolkit)) {
    Install-Module -Name FinOpsToolkit -Force -Scope CurrentUser
}
Import-Module FinOpsToolkit
Write-Host "FinOps Toolkit module ready" -ForegroundColor Green

# ============================================================================
# STEP 2: Create Storage Account for Cost Exports
# ============================================================================
Write-Host "`nStep 2: Creating Storage Account for cost exports..." -ForegroundColor Cyan

az storage account create `
    --name $STORAGE_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --location $LOCATION `
    --sku Standard_LRS `
    --kind StorageV2 `
    --enable-hierarchical-namespace true

Write-Host "Storage Account: $STORAGE_ACCOUNT_NAME" -ForegroundColor Green

# Get storage account resource ID
$STORAGE_ACCOUNT_ID = az storage account show `
    --name $STORAGE_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --query id -o tsv

# ============================================================================
# STEP 3: Handle Azure Policy Bypass for Shared Key Access
# ============================================================================
Write-Host "`nStep 3: Configuring storage account for shared key access..." -ForegroundColor Cyan
Write-Host "  Adding SecurityControl:ignore tag to bypass Azure Policy..." -ForegroundColor Gray

# Add tag to bypass Azure Policy that blocks shared key access
az tag create --resource-id $STORAGE_ACCOUNT_ID --tags SecurityControl=ignore

# Enable shared key access (may be blocked by policy without the tag)
az storage account update `
    --name $STORAGE_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --allow-shared-key-access true

Write-Host "Shared key access enabled" -ForegroundColor Green

# Get storage account key
$STORAGE_ACCESS_KEY = az storage account keys list `
    --account-name $STORAGE_ACCOUNT_NAME `
    --resource-group $RESOURCE_GROUP `
    --query "[0].value" -o tsv

# ============================================================================
# STEP 4: Create Blob Container
# ============================================================================
Write-Host "`nStep 4: Creating blob container..." -ForegroundColor Cyan

# Use login auth mode to avoid issues during container creation
az storage container create `
    --name $CONTAINER_NAME `
    --account-name $STORAGE_ACCOUNT_NAME `
    --auth-mode login

Write-Host "Container '$CONTAINER_NAME' created" -ForegroundColor Green

# ============================================================================
# STEP 5: Create Cost Management Export using FinOps Toolkit
# ============================================================================
Write-Host "`nStep 5: Creating Cost Management Export with FinOps Toolkit..." -ForegroundColor Cyan
Write-Host "  This creates a properly structured export that OpenCost can read" -ForegroundColor Gray

# Use FinOps Toolkit to create the export with immediate execution and backfill
New-FinOpsCostExport `
    -Name $EXPORT_NAME `
    -Scope "/subscriptions/$SUBSCRIPTION_ID" `
    -StorageAccountId $STORAGE_ACCOUNT_ID `
    -StorageContainer $CONTAINER_NAME `
    -Dataset "ActualCost" `
    -Execute `
    -Backfill 1

Write-Host "Cost export '$EXPORT_NAME' created and executed" -ForegroundColor Green
Write-Host "  Path: subscriptions/$SUBSCRIPTION_ID/$EXPORT_NAME" -ForegroundColor Gray

# ============================================================================
# STEP 6: Get AKS Kubelet Identity Client ID (for managed identity)
# ============================================================================
Write-Host "`nStep 6: Getting AKS Kubelet Identity..." -ForegroundColor Cyan

$KUBELET_CLIENT_ID = az aks show `
    --resource-group $RESOURCE_GROUP `
    --name $CLUSTER_NAME `
    --query "identityProfile.kubeletidentity.clientId" -o tsv

Write-Host "Kubelet Identity Client ID: $KUBELET_CLIENT_ID" -ForegroundColor Green

# ============================================================================
# STEP 7: Create cloud-integration.json
# ============================================================================
Write-Host "`nStep 7: Creating cloud-integration.json..." -ForegroundColor Cyan

# The path must match where FinOps Toolkit creates the export
$EXPORT_PATH = "subscriptions/$SUBSCRIPTION_ID/$EXPORT_NAME"

$cloudIntegration = @"
{
  "azure": {
    "storage": [
      {
        "subscriptionID": "$SUBSCRIPTION_ID",
        "account": "$STORAGE_ACCOUNT_NAME",
        "container": "$CONTAINER_NAME",
        "path": "$EXPORT_PATH",
        "cloud": "public",
        "authorizer": {
          "accessKey": "$STORAGE_ACCESS_KEY",
          "account": "$STORAGE_ACCOUNT_NAME",
          "authorizerType": "AzureAccessKey"
        }
      }
    ]
  }
}
"@

$cloudIntegration | Out-File -FilePath "cloud-integration.json" -Encoding UTF8
Write-Host "Created cloud-integration.json" -ForegroundColor Green

# ============================================================================
# STEP 8: Create Kubernetes Secret
# ============================================================================
Write-Host "`nStep 8: Creating Kubernetes secret for cloud costs..." -ForegroundColor Cyan

# Delete existing secret if it exists
kubectl delete secret cloud-costs -n opencost 2>$null

# Create new secret
kubectl create secret generic cloud-costs `
    --from-file=cloud-integration.json `
    --namespace opencost

Write-Host "Secret 'cloud-costs' created in opencost namespace" -ForegroundColor Green

# ============================================================================
# STEP 9: Update OpenCost Helm values with all required configurations
# ============================================================================
Write-Host "`nStep 9: Updating OpenCost with Cloud Costs configuration..." -ForegroundColor Cyan

# This values file includes:
# - Cloud costs enabled with secret reference
# - emptyDir volume for /var/configs/db (fixes permission denied error)
# - AZURE_CLIENT_ID for managed identity (fixes multiple identity error)
# - Prometheus external URL
$opencostCloudCostValues = @"
opencost:
  exporter:
    defaultClusterId: "$CLUSTER_NAME"
    extraEnv:
      AZURE_CLIENT_ID: "$KUBELET_CLIENT_ID"
    extraVolumeMounts:
      - mountPath: /var/secrets
        name: service-key-secret
      - mountPath: /var/configs/db
        name: cloud-cost-db
  cloudIntegrationSecret: cloud-costs
  cloudCost:
    enabled: true
  prometheus:
    internal:
      enabled: false
    external:
      enabled: true
      url: "http://prometheus-server.prometheus-system.svc.cluster.local"
  ui:
    enabled: true
service:
  type: LoadBalancer
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
extraVolumes:
  - name: service-key-secret
    secret:
      secretName: azure-service-key
  - name: cloud-cost-db
    emptyDir: {}
"@

$opencostCloudCostValues | Out-File -FilePath "opencost-values.yaml" -Encoding UTF8

# Upgrade OpenCost with cloud costs enabled
helm upgrade opencost `
    --repo https://opencost.github.io/opencost-helm-chart opencost `
    --namespace opencost `
    -f opencost-values.yaml

Write-Host "OpenCost upgraded with Cloud Costs enabled" -ForegroundColor Green

# ============================================================================
# STEP 10: Wait for pods to restart
# ============================================================================
Write-Host "`nStep 10: Waiting for OpenCost pods to restart..." -ForegroundColor Cyan

kubectl rollout status deployment/opencost -n opencost --timeout=300s

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Green
Write-Host "AZURE CLOUD COSTS INTEGRATION COMPLETE!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green

# Get OpenCost external IP
$OPENCOST_IP = kubectl get service opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null

Write-Host "`nConfiguration Summary:" -ForegroundColor Cyan
Write-Host "  Storage Account:     $STORAGE_ACCOUNT_NAME" -ForegroundColor White
Write-Host "  Container:           $CONTAINER_NAME" -ForegroundColor White
Write-Host "  Export Name:         $EXPORT_NAME" -ForegroundColor White
Write-Host "  Export Path:         $EXPORT_PATH" -ForegroundColor White
Write-Host "  Subscription:        $SUBSCRIPTION_ID" -ForegroundColor White
Write-Host "  Kubelet Client ID:   $KUBELET_CLIENT_ID" -ForegroundColor White

Write-Host "`nKey Configurations Applied:" -ForegroundColor Yellow
Write-Host "  ✓ SecurityControl:ignore tag (bypasses Azure Policy)" -ForegroundColor White
Write-Host "  ✓ Shared key access enabled on storage account" -ForegroundColor White
Write-Host "  ✓ FinOps Toolkit export with proper path structure" -ForegroundColor White
Write-Host "  ✓ emptyDir volume for /var/configs/db (permission fix)" -ForegroundColor White
Write-Host "  ✓ AZURE_CLIENT_ID set (managed identity fix)" -ForegroundColor White

Write-Host "`nAccess OpenCost:" -ForegroundColor Cyan
if ($OPENCOST_IP) {
    Write-Host "  UI:  http://$OPENCOST_IP`:9090" -ForegroundColor White
    Write-Host "  API: http://$OPENCOST_IP`:9090/model/cloudCost?window=7d&aggregate=service" -ForegroundColor White
} else {
    Write-Host "  Run: kubectl get svc opencost -n opencost" -ForegroundColor White
}

Write-Host "`nVerify Cloud Costs Data:" -ForegroundColor Cyan
Write-Host "  kubectl logs deployment/opencost -n opencost -c opencost | Select-String 'retrieved|ingest'" -ForegroundColor White

Write-Host "`nIMPORTANT NOTES:" -ForegroundColor Yellow
Write-Host "  - Cloud costs data may take a few minutes to appear after export runs" -ForegroundColor White
Write-Host "  - The export runs daily and stores data in the storage account" -ForegroundColor White
Write-Host "  - OpenCost reads the exported CSV files from blob storage" -ForegroundColor White
Write-Host "  - Check logs if data doesn't appear: kubectl logs deployment/opencost -n opencost -c opencost" -ForegroundColor White
