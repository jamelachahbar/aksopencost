#!/usr/bin/env pwsh
#############################################################################
# OpenCost on AKS - Bicep Deployment Script
# 
# This script deploys OpenCost on Azure Kubernetes Service using Bicep
#
# Prerequisites:
# - Azure CLI installed
# - Helm installed
# - kubectl installed
# - PowerShell 7+
# - Azure subscription with appropriate permissions
#
# Usage:
#   .\deploy.ps1                    # Full deployment with login
#   .\deploy.ps1 -SkipLogin         # Skip Azure login
#   .\deploy.ps1 -ParametersFile "custom-params.json"  # Use custom parameters
#############################################################################

param(
    [switch]$SkipLogin,
    [string]$ParametersFile = "parameters.json",
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost on AKS - Bicep Deployment" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

# ============================================================================
# STEP 1: Login to Azure
# ============================================================================
Write-Host "`nStep 1: Azure Authentication..." -ForegroundColor Cyan

if (-not $SkipLogin) {
    Write-Host "  Logging in to Azure..." -ForegroundColor Gray
    az login
}

# Set subscription if provided
if ($SubscriptionId) {
    az account set --subscription $SubscriptionId
}

# Get subscription details
$SUBSCRIPTION_ID = az account show --query id -o tsv
$SUBSCRIPTION_NAME = az account show --query name -o tsv
$TENANT_ID = az account show --query tenantId -o tsv
Write-Host "  Using subscription: $SUBSCRIPTION_NAME" -ForegroundColor Green
Write-Host "  Subscription ID: $SUBSCRIPTION_ID" -ForegroundColor Gray

# ============================================================================
# STEP 2: Deploy Infrastructure with Bicep
# ============================================================================
Write-Host "`nStep 2: Deploying infrastructure with Bicep..." -ForegroundColor Cyan

$bicepFile = Join-Path $scriptPath "main.bicep"
$paramsFile = Join-Path $scriptPath $ParametersFile

if (-not (Test-Path $paramsFile)) {
    Write-Host "  ✗ Parameters file not found: $paramsFile" -ForegroundColor Red
    Write-Host "  Copy parameters.example.json to parameters.json and customize" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Deploying Bicep template..." -ForegroundColor Gray
$deployment = az deployment sub create `
    --location "swedencentral" `
    --template-file $bicepFile `
    --parameters "@$paramsFile" `
    --query properties.outputs `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n✗ Bicep deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host "  ✓ Infrastructure deployed" -ForegroundColor Green

# Extract outputs
$RESOURCE_GROUP = $deployment.resourceGroupName.value
$CLUSTER_NAME = $deployment.aksClusterName.value
$SERVICE_PRINCIPAL_APP_ID = $deployment.servicePrincipalAppId.value
$STORAGE_ACCOUNT_NAME = $deployment.storageAccountName.value
$STORAGE_ACCOUNT_KEY = $deployment.storageAccountKey.value
$CONTAINER_NAME = $deployment.costExportContainerName.value

# ============================================================================
# STEP 3: Create Service Principal
# ============================================================================
Write-Host "`nStep 3: Creating Service Principal..." -ForegroundColor Cyan

# Get the unique suffix
$uniqueSuffix = $RESOURCE_GROUP.Substring($RESOURCE_GROUP.Length - 4)
$SP_DISPLAY_NAME = "OpenCostAccess-$uniqueSuffix"
$ROLE_NAME = "OpenCostRole-$uniqueSuffix"

# Check if service principal already exists
$existingSp = az ad sp list --display-name $SP_DISPLAY_NAME --query "[0]" -o json 2>$null | ConvertFrom-Json

if ($existingSp) {
    Write-Host "  Service Principal '$SP_DISPLAY_NAME' exists, resetting credentials..." -ForegroundColor Yellow
    $APP_ID = $existingSp.appId
    
    # Reset credentials
    $spOutput = az ad sp credential reset --id $APP_ID --output json | ConvertFrom-Json
    $PASSWORD = $spOutput.password
    
    Write-Host "  ✓ Service Principal credentials reset" -ForegroundColor Green
} else {
    Write-Host "  Creating new Service Principal '$SP_DISPLAY_NAME'..." -ForegroundColor Gray
    
    # Get the role definition ID
    $roleDefId = az role definition list --name $ROLE_NAME --query "[0].id" -o tsv
    
    if (-not $roleDefId) {
        Write-Host "  ✗ Custom role '$ROLE_NAME' not found. Ensure Bicep deployment succeeded." -ForegroundColor Red
        exit 1
    }
    
    # Create service principal with custom role
    $spOutput = az ad sp create-for-rbac `
        --name $SP_DISPLAY_NAME `
        --role $ROLE_NAME `
        --scopes "/subscriptions/$SUBSCRIPTION_ID" `
        --output json | ConvertFrom-Json
    
    $APP_ID = $spOutput.appId
    $PASSWORD = $spOutput.password
    
    Write-Host "  ✓ Service Principal created" -ForegroundColor Green
}

Write-Host "  App ID: $APP_ID" -ForegroundColor Gray

# ============================================================================
# STEP 4: Get AKS Credentials
# ============================================================================
Write-Host "`nStep 4: Getting AKS credentials..." -ForegroundColor Cyan

az aks get-credentials `
    --resource-group $RESOURCE_GROUP `
    --name $CLUSTER_NAME `
    --overwrite-existing

Write-Host "  ✓ AKS credentials configured" -ForegroundColor Green

# ============================================================================
# STEP 5: Create Kubernetes Namespaces
# ============================================================================
Write-Host "`nStep 5: Creating Kubernetes namespaces..." -ForegroundColor Cyan

kubectl create namespace prometheus-system 2>$null
kubectl create namespace opencost 2>$null
kubectl create namespace sample-app 2>$null

Write-Host "  ✓ Namespaces created" -ForegroundColor Green

# ============================================================================
# STEP 6: Create Kubernetes Secrets
# ============================================================================
Write-Host "`nStep 6: Creating Kubernetes secrets..." -ForegroundColor Cyan

# Create service key secret
$serviceKey = @"
{
    "subscriptionId": "$SUBSCRIPTION_ID",
    "serviceKey": {
        "appId": "$APP_ID",
        "displayName": "$SP_DISPLAY_NAME",
        "password": "$PASSWORD",
        "tenant": "$TENANT_ID"
    }
}
"@

$serviceKey | Out-File -FilePath "service-key.json" -Encoding UTF8
kubectl delete secret azure-service-key -n opencost 2>$null
kubectl create secret generic azure-service-key -n opencost --from-file=service-key.json

# Create storage secret (if cloud costs enabled)
if ($STORAGE_ACCOUNT_NAME) {
    $storageConfig = @"
{
    "azureStorageAccount": "$STORAGE_ACCOUNT_NAME",
    "azureStorageAccessKey": "$STORAGE_ACCOUNT_KEY",
    "azureStorageContainer": "$CONTAINER_NAME",
    "azureContainerPath": "/subscriptions/$SUBSCRIPTION_ID",
    "azureCloud": "public"
}
"@
    
    $storageConfig | Out-File -FilePath "azure-storage-config.json" -Encoding UTF8
    kubectl delete secret azure-storage-config -n opencost 2>$null
    kubectl create secret generic azure-storage-config -n opencost --from-file=azure-storage-config.json
}

Write-Host "  ✓ Secrets created" -ForegroundColor Green

# ============================================================================
# STEP 7: Install Prometheus
# ============================================================================
Write-Host "`nStep 7: Installing Prometheus..." -ForegroundColor Cyan

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create Prometheus values file
$prometheusValues = @"
prometheus-pushgateway:
  enabled: false
alertmanager:
  enabled: false
extraScrapeConfigs: |
  - job_name: opencost
    honor_labels: true
    scrape_interval: 1m
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: http
    dns_sd_configs:
    - names:
      - opencost.opencost
      type: 'A'
      port: 9003
  - job_name: opencost-networking-costs
    honor_labels: true
    scrape_interval: 1m
    scrape_timeout: 10s
    metrics_path: /metrics
    scheme: http
    dns_sd_configs:
    - names:
      - opencost.opencost
      type: 'A'
      port: 9005
"@

$prometheusValues | Out-File -FilePath "prometheus-values.yaml" -Encoding UTF8

helm upgrade --install prometheus prometheus-community/prometheus `
    --namespace prometheus-system `
    -f prometheus-values.yaml

Write-Host "  Waiting for Prometheus to be ready..." -ForegroundColor Yellow
kubectl rollout status deployment/prometheus-server -n prometheus-system --timeout=300s

Write-Host "  ✓ Prometheus installed" -ForegroundColor Green

# ============================================================================
# STEP 8: Install OpenCost
# ============================================================================
Write-Host "`nStep 8: Installing OpenCost..." -ForegroundColor Cyan

helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

# Create OpenCost values file
$opencostValues = @"
opencost:
  exporter:
    defaultClusterId: "$CLUSTER_NAME"
    extraVolumeMounts:
      - mountPath: /var/secrets
        name: service-key-secret
"@

if ($STORAGE_ACCOUNT_NAME) {
    $opencostValues += @"

      - mountPath: /var/azure-storage-config
        name: azure-storage-config
    extraEnv:
      AZURE_STORAGE_ACCOUNT: "$STORAGE_ACCOUNT_NAME"
      AZURE_STORAGE_CONTAINER: "$CONTAINER_NAME"
      AZURE_CONTAINER_PATH: "/subscriptions/$SUBSCRIPTION_ID"
"@
}

$opencostValues += @"

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
"@

if ($STORAGE_ACCOUNT_NAME) {
    $opencostValues += @"

  - name: azure-storage-config
    secret:
      secretName: azure-storage-config
"@
}

$opencostValues | Out-File -FilePath "opencost-values.yaml" -Encoding UTF8

helm upgrade --install opencost opencost/opencost `
    --namespace opencost `
    -f opencost-values.yaml

Write-Host "  Waiting for OpenCost to be ready..." -ForegroundColor Yellow
kubectl rollout status deployment/opencost -n opencost --timeout=300s

Write-Host "  ✓ OpenCost installed" -ForegroundColor Green

# ============================================================================
# STEP 9: Get OpenCost External URL
# ============================================================================
Write-Host "`nStep 9: Getting OpenCost external URL..." -ForegroundColor Cyan

Write-Host "  Waiting for LoadBalancer IP (this may take a minute)..." -ForegroundColor Yellow
$maxRetries = 30
$retryCount = 0
$OPENCOST_IP = ""

while ($retryCount -lt $maxRetries) {
    $OPENCOST_IP = kubectl get service opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    if ($OPENCOST_IP -and $OPENCOST_IP -ne "") {
        break
    }
    Start-Sleep -Seconds 10
    $retryCount++
}

# ============================================================================
# COMPLETE
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green

Write-Host "`nDeployed Resources:" -ForegroundColor Cyan
Write-Host "  ✓ Resource Group: $RESOURCE_GROUP" -ForegroundColor White
Write-Host "  ✓ AKS Cluster: $CLUSTER_NAME" -ForegroundColor White
Write-Host "  ✓ Prometheus: prometheus-system namespace" -ForegroundColor White
Write-Host "  ✓ OpenCost: opencost namespace" -ForegroundColor White
if ($STORAGE_ACCOUNT_NAME) {
    Write-Host "  ✓ Storage Account: $STORAGE_ACCOUNT_NAME" -ForegroundColor White
    Write-Host "  ✓ Cost Export: Configured" -ForegroundColor White
}

if ($OPENCOST_IP) {
    Write-Host "`nAccess OpenCost:" -ForegroundColor Cyan
    Write-Host "  UI:  http://$OPENCOST_IP`:9090" -ForegroundColor White
    Write-Host "  API: http://$OPENCOST_IP`:9003/allocation/compute?window=1h" -ForegroundColor White
} else {
    Write-Host "`nOpenCost external IP not yet available. Get it manually:" -ForegroundColor Yellow
    Write-Host "  kubectl get service opencost -n opencost" -ForegroundColor White
}

Write-Host "`nCleanup:" -ForegroundColor Cyan
Write-Host "  az group delete --name $RESOURCE_GROUP --yes --no-wait" -ForegroundColor White
Write-Host "  az ad sp delete --id $APP_ID" -ForegroundColor White
Write-Host "  az role definition delete --name '$ROLE_NAME'" -ForegroundColor White

# Clean up temporary files
Remove-Item -Path "service-key.json" -ErrorAction SilentlyContinue
Remove-Item -Path "azure-storage-config.json" -ErrorAction SilentlyContinue
Remove-Item -Path "prometheus-values.yaml" -ErrorAction SilentlyContinue
Remove-Item -Path "opencost-values.yaml" -ErrorAction SilentlyContinue
