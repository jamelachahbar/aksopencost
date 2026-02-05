#############################################################################
# Azure CLI Commands to Deploy AKS with Sample App and OpenCost
# 
# This script creates an AKS cluster, deploys a sample application, and 
# installs OpenCost for Kubernetes cost monitoring.
#
# Prerequisites:
# - Azure CLI installed (https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
# - Helm installed (https://helm.sh/docs/intro/install/)
# - kubectl installed (https://kubernetes.io/docs/tasks/tools/)
# - PowerShell 7+ (https://docs.microsoft.com/powershell/scripting/install/installing-powershell)
# - Azure subscription with Contributor + User Access Administrator roles
#
# AKS Requirements:
# - Managed Identity enabled (for Azure API access)
# - Azure CNI network plugin (recommended for production)
# - Minimum 2 nodes with 2 vCPU / 4GB RAM each
#############################################################################

param(
    [switch]$SkipLogin,
    [string]$SubscriptionId
)

# ============================================================================
# CONFIGURATION - Update these variables before running
# ============================================================================
$RESOURCE_GROUP = "rg-opencost-demo"
$LOCATION = "swedencentral"
$AKS_CLUSTER_NAME = "aks-opencost-demo"
$NODE_COUNT = 2
$NODE_VM_SIZE = "Standard_D2s_v5"  # 2 vCPU, 8 GB RAM - minimum recommended

$ErrorActionPreference = "Stop"

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost on AKS - Deployment Script" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

# ============================================================================
# PREREQUISITE CHECKS
# ============================================================================
Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

# Check Azure CLI
$azVersion = az version 2>$null | ConvertFrom-Json
if (-not $azVersion) {
    Write-Host "  ✗ Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green

# Check Helm
$helmVersion = helm version --short 2>$null
if (-not $helmVersion) {
    Write-Host "  ✗ Helm not found. Install from: https://helm.sh/docs/intro/install/" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ Helm version: $helmVersion" -ForegroundColor Green

# Check kubectl
$kubectlVersion = kubectl version --client -o json 2>$null | ConvertFrom-Json
if (-not $kubectlVersion) {
    Write-Host "  ✗ kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/" -ForegroundColor Red
    exit 1
}
Write-Host "  ✓ kubectl version: $($kubectlVersion.clientVersion.gitVersion)" -ForegroundColor Green

Write-Host "`nAll prerequisites met!" -ForegroundColor Green

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

# Get and display current subscription
$SUBSCRIPTION_ID = az account show --query id -o tsv
$SUBSCRIPTION_NAME = az account show --query name -o tsv
Write-Host "  Using subscription: $SUBSCRIPTION_NAME" -ForegroundColor Green
Write-Host "  Subscription ID: $SUBSCRIPTION_ID" -ForegroundColor Gray

# ============================================================================
# STEP 2: Register Required Resource Providers
# ============================================================================
Write-Host "`nStep 2: Registering required resource providers..." -ForegroundColor Cyan

$providers = @(
    "Microsoft.ContainerService",
    "Microsoft.Compute", 
    "Microsoft.Network",
    "Microsoft.Storage",
    "Microsoft.CostManagement"
)

foreach ($provider in $providers) {
    $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if ($state -ne "Registered") {
        Write-Host "  Registering $provider..." -ForegroundColor Gray
        az provider register --namespace $provider
    } else {
        Write-Host "  ✓ $provider already registered" -ForegroundColor Green
    }
}

# ============================================================================
# STEP 3: Create Resource Group
# ============================================================================
Write-Host "`nStep 3: Creating Resource Group..." -ForegroundColor Cyan

az group create `
    --name $RESOURCE_GROUP `
    --location $LOCATION `
    --output none

Write-Host "  ✓ Resource group '$RESOURCE_GROUP' created in $LOCATION" -ForegroundColor Green

# ============================================================================
# STEP 4: Create AKS Cluster
# ============================================================================
Write-Host "`nStep 4: Creating AKS Cluster (this may take 5-10 minutes)..." -ForegroundColor Cyan
Write-Host "  Cluster: $AKS_CLUSTER_NAME" -ForegroundColor Gray
Write-Host "  Nodes: $NODE_COUNT x $NODE_VM_SIZE" -ForegroundColor Gray
Write-Host "  Network: Azure CNI" -ForegroundColor Gray

az aks create `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_CLUSTER_NAME `
    --node-count $NODE_COUNT `
    --node-vm-size $NODE_VM_SIZE `
    --enable-managed-identity `
    --generate-ssh-keys `
    --network-plugin azure `
    --network-policy azure `
    --output none

Write-Host "  ✓ AKS cluster created" -ForegroundColor Green

# ============================================================================
# STEP 5: Get AKS Credentials
# ============================================================================
Write-Host "`nStep 5: Getting AKS credentials..." -ForegroundColor Cyan

az aks get-credentials `
    --resource-group $RESOURCE_GROUP `
    --name $AKS_CLUSTER_NAME `
    --overwrite-existing

# Verify cluster connection
Write-Host "  Verifying cluster connection..." -ForegroundColor Gray
kubectl get nodes -o wide | Out-Null
Write-Host "  ✓ Connected to AKS cluster" -ForegroundColor Green

# ============================================================================
# STEP 6: Create OpenCost Custom Role for Azure Pricing API
# ============================================================================
Write-Host "`nStep 6: Creating OpenCost custom role for Azure pricing..." -ForegroundColor Cyan

# Check if role already exists
$existingRole = az role definition list --name "OpenCostRole" --query "[0].name" -o tsv 2>$null
if ($existingRole) {
    Write-Host "  ✓ OpenCostRole already exists" -ForegroundColor Green
} else {
    $roleDefinition = @"
{
    "Name": "OpenCostRole",
    "IsCustom": true,
    "Description": "Rate Card query role for OpenCost",
    "Actions": [
        "Microsoft.Compute/virtualMachines/vmSizes/read",
        "Microsoft.Resources/subscriptions/locations/read",
        "Microsoft.Resources/providers/read",
        "Microsoft.ContainerService/containerServices/read",
        "Microsoft.Commerce/RateCard/read"
    ],
    "AssignableScopes": [
        "/subscriptions/$SUBSCRIPTION_ID"
    ]
}
"@

    $roleDefinition | Out-File -FilePath "opencost-role.json" -Encoding UTF8
    az role definition create --role-definition "@opencost-role.json" --output none
    Write-Host "  ✓ OpenCostRole created" -ForegroundColor Green
}

# ============================================================================
# STEP 6: Create Service Principal for OpenCost (Azure RateCard Pricing API)
# ============================================================================
Write-Host "`nStep 6: Creating/Updating Service Principal for OpenCost..." -ForegroundColor Cyan

# Check if service principal already exists
$existingSp = az ad sp list --display-name "OpenCostAccess" --query "[0]" -o json 2>$null | ConvertFrom-Json

if ($existingSp) {
    Write-Host "  Service Principal 'OpenCostAccess' exists, resetting credentials..." -ForegroundColor Yellow
    $APP_ID = $existingSp.appId
    
    # Reset credentials to get a new password
    $spOutput = az ad sp credential reset `
        --id $APP_ID `
        --output json | ConvertFrom-Json
    
    $PASSWORD = $spOutput.password
    $TENANT_ID = $spOutput.tenant
    
    # Ensure role assignment exists
    $roleAssignment = az role assignment list --assignee $APP_ID --role "OpenCostRole" --scope "/subscriptions/$SUBSCRIPTION_ID" --query "[0]" -o json 2>$null
    if (-not $roleAssignment -or $roleAssignment -eq "null") {
        Write-Host "  Adding OpenCostRole assignment..." -ForegroundColor Gray
        az role assignment create --assignee $APP_ID --role "OpenCostRole" --scope "/subscriptions/$SUBSCRIPTION_ID" --output none 2>$null
    }
    
    Write-Host "  ✓ Service Principal credentials reset" -ForegroundColor Green
} else {
    Write-Host "  Creating new Service Principal 'OpenCostAccess'..." -ForegroundColor Gray
    $spOutput = az ad sp create-for-rbac `
        --name "OpenCostAccess" `
        --role "OpenCostRole" `
        --scopes "/subscriptions/$SUBSCRIPTION_ID" `
        --output json | ConvertFrom-Json

    $APP_ID = $spOutput.appId
    $PASSWORD = $spOutput.password
    $TENANT_ID = $spOutput.tenant
    
    Write-Host "  ✓ Service Principal created" -ForegroundColor Green
}

Write-Host "  App ID: $APP_ID" -ForegroundColor Gray

# ============================================================================
# STEP 7: Create service-key.json for OpenCost
# ============================================================================
Write-Host "`nStep 7: Creating service-key.json..." -ForegroundColor Cyan

$serviceKey = @"
{
    "subscriptionId": "$SUBSCRIPTION_ID",
    "serviceKey": {
        "appId": "$APP_ID",
        "displayName": "OpenCostAccess",
        "password": "$PASSWORD",
        "tenant": "$TENANT_ID"
    }
}
"@

$serviceKey | Out-File -FilePath "service-key.json" -Encoding UTF8

# ============================================================================
# STEP 8: Install Prometheus (required for OpenCost)
# ============================================================================
Write-Host "`nStep 8: Installing Prometheus..." -ForegroundColor Cyan

# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install or upgrade Prometheus with OpenCost scrape configuration
helm upgrade --install prometheus prometheus-community/prometheus `
    --namespace prometheus-system `
    --create-namespace `
    --set prometheus-pushgateway.enabled=false `
    --set alertmanager.enabled=false `
    -f https://raw.githubusercontent.com/opencost/opencost/develop/kubernetes/prometheus/extraScrapeConfigs.yaml

# Wait for Prometheus to be ready
Write-Host "Waiting for Prometheus pods to be ready..." -ForegroundColor Yellow
kubectl rollout status deployment/prometheus-server -n prometheus-system --timeout=300s

# ============================================================================
# STEP 9: Create OpenCost Namespace and Secret
# ============================================================================
Write-Host "`nStep 9: Creating OpenCost namespace and secret..." -ForegroundColor Cyan

# Create namespace if it doesn't exist
kubectl create namespace opencost 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Namespace 'opencost' already exists" -ForegroundColor Gray
}

# Delete existing secret and recreate with new credentials
kubectl delete secret azure-service-key -n opencost 2>$null
kubectl create secret generic azure-service-key `
    -n opencost `
    --from-file=service-key.json

Write-Host "  ✓ Azure service key secret created/updated" -ForegroundColor Green

# ============================================================================
# STEP 10: Install OpenCost
# ============================================================================
Write-Host "`nStep 10: Installing OpenCost..." -ForegroundColor Cyan

# Add OpenCost Helm repository
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

# Create OpenCost values file with LoadBalancer service type for public Azure URL
$opencostValues = @"
opencost:
  exporter:
    defaultClusterId: "$AKS_CLUSTER_NAME"
    extraVolumeMounts:
      - mountPath: /var/secrets
        name: service-key-secret
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

$opencostValues | Out-File -FilePath "opencost-values.yaml" -Encoding UTF8

# Install or upgrade OpenCost with Helm
helm upgrade --install opencost opencost/opencost `
    --namespace opencost `
    -f opencost-values.yaml

# Wait for OpenCost to be ready
Write-Host "Waiting for OpenCost pods to be ready..." -ForegroundColor Yellow
kubectl rollout status deployment/opencost -n opencost --timeout=300s

# ============================================================================
# STEP 11: Deploy Sample Application
# ============================================================================
Write-Host "`nStep 11: Deploying sample application..." -ForegroundColor Cyan

# Create a sample namespace (ignore if exists)
kubectl create namespace sample-app 2>$null

# Deploy a sample nginx application
$sampleApp = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-sample
  namespace: sample-app
  labels:
    app: nginx-sample
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx-sample
  template:
    metadata:
      labels:
        app: nginx-sample
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "250m"
            memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-sample-service
  namespace: sample-app
spec:
  type: LoadBalancer
  selector:
    app: nginx-sample
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-sample
  namespace: sample-app
  labels:
    app: redis-sample
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-sample
  template:
    metadata:
      labels:
        app: redis-sample
    spec:
      containers:
      - name: redis
        image: redis:alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            cpu: "50m"
            memory: "64Mi"
          limits:
            cpu: "100m"
            memory: "128Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: redis-sample-service
  namespace: sample-app
spec:
  type: ClusterIP
  selector:
    app: redis-sample
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
"@

$sampleApp | Out-File -FilePath "sample-app.yaml" -Encoding UTF8
kubectl apply -f sample-app.yaml

# Wait for sample app to be ready
Write-Host "Waiting for sample application pods to be ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=nginx-sample -n sample-app --timeout=300s

# ============================================================================
# STEP 12: Verify Deployment
# ============================================================================
Write-Host "`nStep 12: Verifying deployment..." -ForegroundColor Cyan

Write-Host "`n=== Cluster Nodes ===" -ForegroundColor Yellow
kubectl get nodes

Write-Host "`n=== Prometheus Pods ===" -ForegroundColor Yellow
kubectl get pods -n prometheus-system

Write-Host "`n=== OpenCost Pods ===" -ForegroundColor Yellow
kubectl get pods -n opencost

Write-Host "`n=== Sample Application Pods ===" -ForegroundColor Yellow
kubectl get pods -n sample-app

Write-Host "`n=== All Services ===" -ForegroundColor Yellow
kubectl get services --all-namespaces

# ============================================================================
# STEP 13: Get OpenCost External URL
# ============================================================================
Write-Host "`nStep 13: Getting OpenCost external URL..." -ForegroundColor Cyan

# Wait for LoadBalancer to get external IP
Write-Host "Waiting for OpenCost LoadBalancer to get external IP (this may take a minute)..." -ForegroundColor Yellow
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
    Write-Host "  Waiting for external IP... ($retryCount/$maxRetries)" -ForegroundColor Gray
}

# ============================================================================
# STEP 14: Access Instructions
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Green
Write-Host "DEPLOYMENT COMPLETE!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green

if ($OPENCOST_IP) {
    Write-Host "`nOpenCost is accessible via Azure LoadBalancer:" -ForegroundColor Cyan
    Write-Host "  - OpenCost UI: http://$OPENCOST_IP`:9090" -ForegroundColor White
    Write-Host "  - OpenCost API: http://$OPENCOST_IP`:9003/allocation/compute?window=60m" -ForegroundColor White
} else {
    Write-Host "`nOpenCost external IP not yet available. Get it manually:" -ForegroundColor Yellow
    Write-Host "  kubectl get service opencost -n opencost" -ForegroundColor White
}

Write-Host "`nAlternatively, use port-forward for local access:" -ForegroundColor Cyan
Write-Host "  kubectl port-forward --namespace opencost service/opencost 9003 9090" -ForegroundColor White

Write-Host "`nTo access Prometheus UI, run:" -ForegroundColor Cyan
Write-Host "  kubectl port-forward --namespace prometheus-system service/prometheus-server 9080:80" -ForegroundColor White

Write-Host "`nThen open your browser to:" -ForegroundColor Cyan
Write-Host "  - Prometheus UI: http://localhost:9080" -ForegroundColor White

Write-Host "`nTo access the sample nginx app externally, run:" -ForegroundColor Cyan
Write-Host "  kubectl get service nginx-sample-service -n sample-app" -ForegroundColor White

Write-Host "`nTo get cost allocation by namespace:" -ForegroundColor Cyan
Write-Host "  curl http://localhost:9003/allocation/compute?window=1h&aggregate=namespace" -ForegroundColor White

Write-Host "`n============================================================================" -ForegroundColor Green
Write-Host "CLEANUP INSTRUCTIONS" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Green
Write-Host "`nTo delete all resources when done:" -ForegroundColor Cyan
Write-Host "  az group delete --name $RESOURCE_GROUP --yes --no-wait" -ForegroundColor White
Write-Host "  az ad sp delete --id $APP_ID" -ForegroundColor White
Write-Host "  az role definition delete --name 'OpenCostRole'" -ForegroundColor White
