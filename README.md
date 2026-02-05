# OpenCost on Azure Kubernetes Service (AKS)

A complete, **fully automated** solution for deploying [OpenCost](https://www.opencost.io/) on Azure Kubernetes Service with **Azure Cloud Costs** integration.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [AKS Requirements](#aks-requirements)
- [Cost Export Requirements](#cost-export-requirements)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Deployment Checklist](#deployment-checklist)
- [Detailed Setup Guide](#detailed-setup-guide)
- [Azure Cloud Costs Integration](#azure-cloud-costs-integration)
- [Cost Allocation & Export](#cost-allocation--export)
- [Testing & Validation](#testing--validation)
- [Troubleshooting](#troubleshooting)
- [Commands Reference](#commands-reference)
- [File Structure](#file-structure)
- [Useful Links](#useful-links)
- [Cleanup](#cleanup)

---

## Overview

This repository contains **fully automated scripts** to deploy OpenCost on AKS. Just run two scripts and everything is configured:

```powershell
.\deploy-aks-opencost.ps1      # Creates AKS + installs OpenCost
.\setup-azure-cloud-costs.ps1  # Configures Azure billing integration
```

### What Gets Deployed

- ✅ **AKS Cluster** - Managed Kubernetes with Azure CNI
- ✅ **Prometheus** - Metrics collection for Kubernetes costs
- ✅ **OpenCost** - Real-time cost monitoring UI and API
- ✅ **Azure Cloud Costs** - Full Azure billing data integration
- ✅ **Sample Applications** - nginx/redis for testing cost allocation

### What is OpenCost?

OpenCost is a CNCF sandbox project that provides real-time cost monitoring for Kubernetes clusters. It shows:
- **Kubernetes costs**: CPU, memory, storage, network by namespace/pod/deployment
- **Cloud costs**: Full Azure billing data (VMs, storage, networking, services)

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose | Installation |
|------|---------|---------|--------------|
| **Azure CLI** | 2.50+ | Azure resource management | [Install Guide](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| **kubectl** | 1.25+ | Kubernetes management | [Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | 3.10+ | Kubernetes package manager | [Install Guide](https://helm.sh/docs/intro/install/) |
| **PowerShell** | 7.0+ | Script execution | [Install Guide](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) |

> 💡 **Note**: The FinOps Toolkit module is automatically installed by the script if not present.

### Azure RBAC Requirements

| Role | Scope | Purpose |
|------|-------|---------|
| **Contributor** | Subscription or Resource Group | Create AKS, Storage, etc. |
| **User Access Administrator** | Subscription | Create custom roles and service principals |
| **Cost Management Reader** | Subscription | Create cost exports |

### Verify Prerequisites

The deployment script automatically checks all prerequisites. You can also verify manually:

```powershell
# Check Azure CLI
az --version

# Check kubectl
kubectl version --client

# Check Helm
helm version

# Login to Azure
az login
az account show
```

---

## AKS Requirements

### Cluster Configuration

OpenCost requires specific AKS features to function correctly:

| Feature | Required | Value | Purpose |
|---------|----------|-------|---------|
| **Managed Identity** | ✅ Yes | `--enable-managed-identity` | Azure API authentication |
| **Network Plugin** | Recommended | `azure` (CNI) | Better network visibility |
| **Node Count** | Minimum | 2 nodes | High availability |
| **Node Size** | Minimum | 2 vCPU / 4GB RAM | Run OpenCost + Prometheus |

### Supported AKS Configurations

| Configuration | Supported | Notes |
|---------------|-----------|-------|
| **Azure CNI** | ✅ Yes | Recommended for production |
| **Kubenet** | ✅ Yes | Works but less network visibility |
| **Azure CNI Overlay** | ✅ Yes | Works with OpenCost |
| **Private Cluster** | ✅ Yes | Requires VPN/bastion access |
| **Node Pools** | ✅ Yes | Costs tracked per node pool |
| **Spot Instances** | ✅ Yes | Spot pricing reflected |
| **AKS Automatic** | ⚠️ Limited | May have restrictions |

### Minimum Node Specifications

| Component | CPU Request | Memory Request | Notes |
|-----------|-------------|----------------|-------|
| Prometheus | 500m | 512Mi | Scales with metrics volume |
| OpenCost | 100m | 256Mi | Low resource footprint |
| **Total Minimum** | **600m** | **768Mi** | Per node overhead |

**Recommended Node Size**: `Standard_D2s_v5` (2 vCPU, 8 GB RAM) or larger

---

## Cost Export Requirements

### Azure Cost Management Export Settings

OpenCost requires a specific export configuration to read Azure billing data:

| Setting | Required Value | Description |
|---------|----------------|-------------|
| **Dataset Type** | `ActualCost` | Actual billed costs (not amortized) |
| **Export Format** | CSV | OpenCost reads CSV files |
| **Schedule** | Daily | Recommended for fresh data |
| **Time Frame** | Month-to-date | Current billing period |
| **Storage Type** | Blob Storage | With Data Lake Gen2 (hierarchical namespace) |
| **Compression** | None | Uncompressed CSV required |

### Why ActualCost Dataset?

| Dataset Type | Use Case | OpenCost Support |
|--------------|----------|------------------|
| **ActualCost** | Actual charges billed | ✅ Recommended |
| **AmortizedCost** | Spreads reservations | ✅ Supported |
| **Usage** | Usage without costs | ❌ Not supported |

### Export Path Structure

The FinOps Toolkit creates exports with this structure (required by OpenCost):

```
container-name/
└── subscriptions/
    └── {subscription-id}/
        └── {export-name}/
            └── {date-range}/
                └── {guid}/
                    └── part_0_0001.csv    ← OpenCost reads this
```

### Storage Account Requirements

| Setting | Required Value | Purpose |
|---------|----------------|---------|
| **Account Type** | StorageV2 | Required for Data Lake features |
| **Hierarchical Namespace** | Enabled | Data Lake Gen2 support |
| **Access Tier** | Hot | Frequent read access |
| **Shared Key Access** | Enabled | OpenCost authentication |

> ⚠️ **Azure Policy Note**: Many organizations block shared key access via Azure Policy. The script handles this by adding a `SecurityControl:ignore` tag to bypass the policy.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                            │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
│  │   AKS Cluster   │    │ Storage Account │    │ Cost Management │  │
│  │                 │    │                 │    │     Export      │  │
│  │ ┌─────────────┐ │    │  cost-exports   │    │                 │  │
│  │ │ Prometheus  │ │    │   container     │◄───│  Daily Export   │  │
│  │ └──────┬──────┘ │    │                 │    │  (ActualCost)   │  │
│  │        │        │    └────────┬────────┘    └─────────────────┘  │
│  │        ▼        │             │                                   │
│  │ ┌─────────────┐ │             │                                   │
│  │ │  OpenCost   │─┼─────────────┘                                   │
│  │ │             │ │    Reads billing data                          │
│  │ │  - UI       │ │                                                 │
│  │ │  - API      │ │    ┌─────────────────┐                         │
│  │ │  - Metrics  │─┼───►│ Azure Retail    │                         │
│  │ └─────────────┘ │    │ Pricing API     │                         │
│  │                 │    └─────────────────┘                         │
│  │ ┌─────────────┐ │                                                 │
│  │ │ Sample Apps │ │                                                 │
│  │ │ nginx/redis │ │                                                 │
│  │ └─────────────┘ │                                                 │
│  └─────────────────┘                                                 │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### Option 1: Single Command (Recommended)

Deploy everything with one command - no manual steps required:

```powershell
# Clone the repository
cd c:\_repos\aksopencost

# Run complete deployment (15-20 minutes)
.\deploy-all.ps1
```

The script will:
1. ✅ Check all prerequisites
2. ✅ Create AKS cluster with managed identity
3. ✅ Install Prometheus for metrics
4. ✅ Install OpenCost with Azure pricing integration
5. ✅ Create storage account and cost export
6. ✅ Configure cloud costs integration
7. ✅ Verify the deployment

### Option 2: Step-by-Step Deployment

```powershell
# 1. Deploy AKS + Prometheus + OpenCost
.\deploy-aks-opencost.ps1

# 2. Setup Azure Cloud Costs integration
.\setup-azure-cloud-costs.ps1

# 3. Verify the deployment
.\verify-deployment.ps1

# 4. Deploy sample apps (optional)
.\generate-load.ps1
```

### Cleanup

```powershell
# Remove all Azure resources
.\cleanup.ps1
```

---

## Deployment Checklist

### Phase 1: Infrastructure Setup

| Step | Task | Command/Action | Status |
|------|------|----------------|--------|
| 1.1 | Login to Azure | `az login` | ☐ |
| 1.2 | Set subscription | `az account set -s <subscription-id>` | ☐ |
| 1.3 | Create resource group | `az group create -n rg-opencost-demo -l swedencentral` | ☐ |
| 1.4 | Create AKS cluster | `az aks create ...` | ☐ |
| 1.5 | Get AKS credentials | `az aks get-credentials ...` | ☐ |

### Phase 2: OpenCost Deployment

| Step | Task | Command/Action | Status |
|------|------|----------------|--------|
| 2.1 | Create OpenCost namespace | `kubectl create namespace opencost` | ☐ |
| 2.2 | Create Azure custom role | `az role definition create ...` | ☐ |
| 2.3 | Create service principal | `az ad sp create-for-rbac ...` | ☐ |
| 2.4 | Create service-key secret | `kubectl create secret generic azure-service-key ...` | ☐ |
| 2.5 | Install Prometheus | `helm install prometheus ...` | ☐ |
| 2.6 | Install OpenCost | `helm install opencost ...` | ☐ |

### Phase 3: Cloud Costs Integration (Required for Azure billing data)

| Step | Task | Command/Action | Status |
|------|------|----------------|--------|
| 3.1 | Install FinOps Toolkit | `Install-Module -Name FinOpsToolkit` | ☐ |
| 3.2 | Create storage account | `az storage account create ...` | ☐ |
| 3.3 | **Add SecurityControl tag** | `az tag create --resource-id ... --tags SecurityControl=ignore` | ☐ |
| 3.4 | Enable shared key access | `az storage account update --allow-shared-key-access true` | ☐ |
| 3.5 | Create cost export container | `az storage container create --auth-mode login ...` | ☐ |
| 3.6 | Create cost export with FinOps Toolkit | `New-FinOpsCostExport -Execute -Backfill 1 ...` | ☐ |
| 3.7 | Get Kubelet Identity Client ID | `az aks show --query identityProfile.kubeletidentity.clientId` | ☐ |
| 3.8 | Create cloud-integration secret | `kubectl create secret generic cloud-costs ...` | ☐ |
| 3.9 | Upgrade OpenCost with cloud costs | `helm upgrade opencost ... -f opencost-values.yaml` | ☐ |

### Phase 4: Validation

| Step | Task | Expected Result | Status |
|------|------|-----------------|--------|
| 4.1 | Check pods running | All pods in Running state | ☐ |
| 4.2 | Access OpenCost UI | UI loads at `http://<IP>:9090` | ☐ |
| 4.3 | Verify Kubernetes costs | Cost data visible in UI | ☐ |
| 4.4 | Check OpenCost logs | "retrieved ... of size XXX" messages | ☐ |
| 4.5 | Verify Cloud Costs API | `/model/cloudCost?window=7d` returns data | ☐ |

---

## Configuration

Edit the configuration variables at the top of each script:

| Variable | Description | Default |
|----------|-------------|---------|
| `RESOURCE_GROUP` | Azure resource group name | `rg-opencost-demo` |
| `LOCATION` | Azure region | `swedencentral` |
| `AKS_CLUSTER_NAME` | AKS cluster name | `aks-opencost-demo` |
| `NODE_COUNT` | Number of nodes | `2` |
| `NODE_VM_SIZE` | VM size for nodes | `Standard_D2s_v5` |

---

## Detailed Setup Guide

### Step 1: Deploy AKS + OpenCost (Basic)

Run the main deployment script:

```powershell
.\deploy-aks-opencost.ps1
```

This script:
1. Creates an Azure resource group
2. Creates an AKS cluster with managed identity
3. Creates a custom Azure role for OpenCost pricing API access
4. Creates a service principal for OpenCost
5. Installs Prometheus for metrics
6. Installs OpenCost with LoadBalancer service
7. Deploys sample applications (nginx, redis)

### Step 2: Setup Azure Cloud Costs Integration

Run the cloud costs setup script:

```powershell
.\setup-azure-cloud-costs.ps1
```

This script uses the **FinOps Toolkit** to:
1. Create a storage account with proper tags for policy bypass
2. Enable shared key access on the storage account
3. Create a cost export using `New-FinOpsCostExport`
4. Execute the export immediately and backfill historical data
5. Configure OpenCost with the correct cloud-integration.json
6. Upgrade OpenCost Helm chart with cloud costs enabled

---

## Azure Cloud Costs Integration

### Overview

Azure Cloud Costs integration allows OpenCost to display actual Azure billing data alongside Kubernetes cost allocations.

### Key Components

| Component | Purpose |
|-----------|---------|
| **Storage Account** | Stores cost export CSV files |
| **Cost Management Export** | Daily export of billing data (ActualCost) |
| **FinOps Toolkit** | PowerShell module for creating exports with proper structure |
| **cloud-integration.json** | OpenCost configuration for Azure storage access |

### Important: Azure Policy Bypass

Many organizations have Azure Policy that blocks shared key access on storage accounts. You **must** add a tag to bypass this:

```powershell
# Get storage account resource ID
$STORAGE_ACCOUNT_ID = az storage account show -n <storage-account-name> -g <resource-group> --query id -o tsv

# Add SecurityControl:ignore tag to bypass policy
az tag create --resource-id $STORAGE_ACCOUNT_ID --tags SecurityControl=ignore

# Then enable shared key access
az storage account update -n <storage-account-name> -g <resource-group> --allow-shared-key-access true
```

> ⚠️ **Note**: Without this tag, you'll see `KeyBasedAuthenticationNotPermitted` errors in OpenCost logs.

### Why FinOps Toolkit?

The FinOps Toolkit's `New-FinOpsCostExport` creates exports with:
- Proper folder structure that OpenCost expects
- Correct path format: `subscriptions/{subscriptionId}/{exportName}`
- Support for immediate execution (`-Execute`) and historical backfill (`-Backfill`)
- Automatic export scheduling

```powershell
# Example: Create export with immediate execution and 1 month backfill
New-FinOpsCostExport `
    -Name "opencost-daily" `
    -Scope "/subscriptions/$SUBSCRIPTION_ID" `
    -StorageAccountId $STORAGE_ACCOUNT_ID `
    -StorageContainer "cost-exports" `
    -Dataset "ActualCost" `
    -Execute `
    -Backfill 1
```

---

## Testing & Validation

### Check Deployment Status

```powershell
# Check all pods
kubectl get pods -A | Select-String "opencost|prometheus"

# Check OpenCost pods specifically
kubectl get pods -n opencost

# Check services
kubectl get svc -n opencost
```

### Access OpenCost UI

```powershell
# Get external IP
$OPENCOST_IP = kubectl get svc opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
Write-Host "OpenCost UI: http://$OPENCOST_IP`:9090"

# Open in browser
Start-Process "http://$OPENCOST_IP`:9090"
```

### Test API Endpoints

```powershell
$OPENCOST_IP = kubectl get svc opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Kubernetes allocation data (by namespace)
curl "http://$OPENCOST_IP`:9090/model/allocation?window=24h&aggregate=namespace"

# Cloud costs (Azure billing data)
curl "http://$OPENCOST_IP`:9090/model/cloudCost?window=7d&aggregate=service"

# Health check
curl "http://$OPENCOST_IP`:9090/healthz"
```

### Verify Cloud Costs Data Ingestion

```powershell
# Check OpenCost logs for successful data retrieval
kubectl logs deployment/opencost -n opencost -c opencost | Select-String "retrieved|ingest"

# Expected output:
# "retrieved .../part_0_0001.csv of size XXX"
# "ingestor: build[...]: completed in XXXms"
```

### Generate Test Load

```powershell
# Deploy sample apps and load generators
.\generate-load.ps1
```

---

## Troubleshooting

### Common Issues

#### 1. "KeyBasedAuthenticationNotPermitted" Error

**Symptom:** OpenCost logs show `KeyBasedAuthenticationNotPermitted` when accessing storage.

**Cause:** Azure Policy blocks shared key access on storage accounts.

**Solution:**
```powershell
# Get storage account resource ID
$STORAGE_ACCOUNT_ID = az storage account show -n <storage-account-name> -g <resource-group> --query id -o tsv

# Add bypass tag
az tag create --resource-id $STORAGE_ACCOUNT_ID --tags SecurityControl=ignore

# Enable shared key access
az storage account update -n <storage-account-name> -g <resource-group> --allow-shared-key-access true
```

#### 2. "ContainerNotFound" Error

**Symptom:** OpenCost logs show `ContainerNotFound`.

**Cause:** The cost-exports container doesn't exist or the path is wrong.

**Solution:**
```powershell
# Create container with login auth (not key auth)
az storage container create --name cost-exports --account-name $STORAGE_ACCOUNT --auth-mode login

# Verify blobs exist
az storage blob list --account-name $STORAGE_ACCOUNT --container-name cost-exports --auth-mode login --query "[].name"
```

#### 3. "mkdir /var/configs/db: permission denied" Error

**Symptom:** OpenCost pod crashes with permission denied creating `/var/configs/db`.

**Cause:** Missing emptyDir volume for cloud cost database.

**Solution:** The `setup-azure-cloud-costs.ps1` script includes this fix. Ensure your `opencost-values.yaml` has:

```yaml
extraVolumes:
  - name: cloud-cost-db
    emptyDir: {}
opencost:
  exporter:
    extraVolumeMounts:
      - mountPath: /var/configs/db
        name: cloud-cost-db
```

#### 4. "Multiple user assigned identities exist" Error

**Symptom:** Managed Identity authentication fails with multiple identity error.

**Cause:** AKS has multiple identities and OpenCost can't determine which to use.

**Solution:** Set the `AZURE_CLIENT_ID` environment variable:

```powershell
# Get kubelet identity client ID
$KUBELET_CLIENT_ID = az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query "identityProfile.kubeletidentity.clientId" -o tsv

# Add to opencost-values.yaml
opencost:
  exporter:
    extraEnv:
      AZURE_CLIENT_ID: "<kubelet-client-id>"
```

#### 5. No Cloud Cost Data Showing

**Symptom:** Cloud Costs page shows "no integrations configured" or no data.

**Checklist:**
1. ✅ Verify `cloudCost.enabled: true` in Helm values
2. ✅ Check `cloudIntegrationSecret: cloud-costs` is set
3. ✅ Verify secret contains valid `cloud-integration.json`
4. ✅ Check cost export has run and data exists in storage
5. ✅ Verify path in cloud-integration.json matches export path

```powershell
# Check secret content
kubectl get secret cloud-costs -n opencost -o jsonpath='{.data.cloud-integration\.json}' | 
    ForEach-Object { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($_)) }

# Check OpenCost logs for cloud/azure related messages
kubectl logs deployment/opencost -n opencost -c opencost | Select-String "cloud|azure|error"

# Check if export data exists in storage
az storage blob list --account-name $STORAGE_ACCOUNT --container-name cost-exports --auth-mode login --query "[].name"
```

#### 6. Export Path Mismatch

**Symptom:** OpenCost can't find the cost data files.

**Cause:** The path in `cloud-integration.json` doesn't match where exports are stored.

**Solution:** Use FinOps Toolkit exports which create a predictable path structure:

```powershell
# Path format created by FinOps Toolkit
# subscriptions/{subscriptionId}/{exportName}

# Example cloud-integration.json path
"path": "subscriptions/e9b4640d-1f1f-45fe-a543-c0ea45ac34c1/opencost-daily"
```

### View Logs

```powershell
# OpenCost logs (live)
kubectl logs deployment/opencost -n opencost -c opencost -f

# Prometheus logs
kubectl logs deployment/prometheus-server -n prometheus-system -f

# Filter for errors
kubectl logs deployment/opencost -n opencost -c opencost | Select-String "error|Error|ERR"

# Filter for cloud cost activity
kubectl logs deployment/opencost -n opencost -c opencost | Select-String "cloud|ingest|retrieved"
```

### Restart Deployments

```powershell
# Restart OpenCost (after config changes)
kubectl rollout restart deployment/opencost -n opencost

# Wait for rollout
kubectl rollout status deployment/opencost -n opencost
```

---

## Commands Reference

### Kubernetes Commands

| Command | Description |
|---------|-------------|
| `kubectl get pods -n opencost` | List OpenCost pods |
| `kubectl get svc -n opencost` | List OpenCost services |
| `kubectl logs deployment/opencost -n opencost -c opencost` | View OpenCost logs |
| `kubectl describe pod -n opencost <pod-name>` | Describe pod details |
| `kubectl rollout restart deployment/opencost -n opencost` | Restart OpenCost |
| `kubectl get secret cloud-costs -n opencost -o yaml` | View cloud-costs secret |

### Azure CLI Commands

| Command | Description |
|---------|-------------|
| `az aks get-credentials -g <rg> -n <cluster>` | Get AKS credentials |
| `az storage account keys list -n <account> -g <rg>` | Get storage keys |
| `az storage blob list --account-name <name> --container-name <container>` | List blobs |
| `az aks show -g <rg> -n <cluster> --query "identityProfile"` | Show AKS identities |

### Helm Commands

| Command | Description |
|---------|-------------|
| `helm list -n opencost` | List Helm releases |
| `helm upgrade opencost ... -f values.yaml` | Upgrade OpenCost |
| `helm uninstall opencost -n opencost` | Uninstall OpenCost |
| `helm get values opencost -n opencost` | Get current values |

### FinOps Toolkit Commands

| Command | Description |
|---------|-------------|
| `Get-FinOpsCostExport -Scope "/subscriptions/<id>"` | List cost exports |
| `New-FinOpsCostExport -Execute -Backfill 1 ...` | Create & run export |
| `Start-FinOpsCostExport -Name <name> -Scope <scope>` | Trigger export run |
| `Remove-FinOpsCostExport -Name <name> -Scope <scope>` | Delete export |

### OpenCost API Endpoints

| Endpoint | Description |
|----------|-------------|
| `/model/allocation?window=24h&aggregate=namespace` | Kubernetes costs by namespace |
| `/model/allocation?window=7d&aggregate=controller` | Costs by controller |
| `/model/cloudCost?window=7d&aggregate=service` | Azure billing by service |
| `/model/cloudCost?window=30d&aggregate=provider` | Cloud costs by provider |
| `/healthz` | Health check |

---

## Useful Links

### OpenCost Documentation
- [OpenCost Website](https://www.opencost.io/)
- [OpenCost GitHub](https://github.com/opencost/opencost)
- [Azure Configuration Guide](https://www.opencost.io/docs/configuration/azure)
- [Cloud Costs Documentation](https://www.opencost.io/docs/configuration/cloud-costs)
- [OpenCost API Reference](https://www.opencost.io/docs/integrations/api)

### Azure Documentation
- [AKS Documentation](https://docs.microsoft.com/azure/aks/)
- [Cost Management Exports](https://docs.microsoft.com/azure/cost-management-billing/costs/tutorial-export-acm-data)
- [Azure Retail Prices API](https://docs.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices)
- [Managed Identities](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)

### FinOps Toolkit
- [FinOps Toolkit GitHub](https://github.com/microsoft/finops-toolkit)
- [FinOps Toolkit Documentation](https://microsoft.github.io/finops-toolkit/)
- [PowerShell Module](https://www.powershellgallery.com/packages/FinOpsToolkit)
- [New-FinOpsCostExport Reference](https://microsoft.github.io/finops-toolkit/powershell/cost/New-FinOpsCostExport)

### Helm Charts
- [OpenCost Helm Chart](https://github.com/opencost/opencost-helm-chart)
- [Prometheus Helm Chart](https://github.com/prometheus-community/helm-charts)

---

## Cleanup

### Delete All Resources

```powershell
# Delete AKS cluster and resource group
az group delete --name rg-opencost-demo --yes --no-wait

# Delete service principal
az ad sp delete --id $(az ad sp list --display-name "OpenCostAccess" --query "[0].id" -o tsv)

# Delete custom role
az role definition delete --name "OpenCostRole"

# Delete cost export
$SUBSCRIPTION_ID = az account show --query id -o tsv
Remove-FinOpsCostExport -Name "opencost-daily" -Scope "/subscriptions/$SUBSCRIPTION_ID" -RemoveData
```

### Delete Only Kubernetes Resources

```powershell
# Uninstall OpenCost
helm uninstall opencost -n opencost

# Uninstall Prometheus
helm uninstall prometheus -n prometheus-system

# Delete namespaces
kubectl delete namespace opencost
kubectl delete namespace prometheus-system
kubectl delete namespace sample-app
```

---

## File Structure

### ✅ Essential Files (Commit to Git)

| File | Purpose | When to Use |
|------|---------|-------------|
| **deploy-all.ps1** | 🚀 **Main entry point** - deploys everything | `.\deploy-all.ps1` |
| **deploy-aks-opencost.ps1** | AKS + Prometheus + OpenCost deployment | Step-by-step setup |
| **setup-azure-cloud-costs.ps1** | Azure billing integration via FinOps Toolkit | After AKS deployment |
| **setup-cost-allocation.ps1** | Apply team/project/cost-center labels | Cost attribution |
| **export-allocation-data.ps1** | Export allocation data for Power BI | Manual exports |
| **setup-allocation-export.ps1** | Automated export CronJob | Scheduled exports |
| **verify-deployment.ps1** | Verify everything is working | Troubleshooting |
| **cleanup.ps1** | Clean up all Azure resources | When done |
| **generate-load.ps1** | Generate load for testing | Testing |
| **sample-app.yaml** | Sample workload manifest | Testing |
| **load-generator.yaml** | Load generator Kubernetes manifest | Load testing |
| **cost-allocation-labels.yaml** | Example cost allocation labels | Reference |
| **README.md** | This documentation | Reference |
| **.gitignore** | Prevents secrets from being committed | Always |

### 🚫 Generated Files (Do NOT Commit - Auto-Created)

| File | Contains | Created By |
|------|----------|------------|
| **service-key.json** | ⚠️ Service principal credentials | `deploy-aks-opencost.ps1` |
| **cloud-integration.json** | ⚠️ Storage account access key | `setup-azure-cloud-costs.ps1` |
| **opencost-values.yaml** | Helm values (environment-specific) | `deploy-aks-opencost.ps1` |
| **opencost-role.json** | Azure custom role definition | `deploy-aks-opencost.ps1` |
| **exports/** | Exported allocation data files | `export-allocation-data.ps1` |

> ⚠️ **Security Note**: All sensitive files are excluded from git via `.gitignore`. Never manually commit these files.

---

## Cost Allocation & Export

### Label-Based Cost Allocation

Attribute costs to teams, projects, or cost centers using Kubernetes labels:

```powershell
# Apply cost allocation labels to workloads
.\setup-cost-allocation.ps1

# Or manually label deployments
kubectl label deployment <name> -n <namespace> \
    team=backend \
    project=customer-api \
    cost-center=CC-2001
```

#### Viewing Label-Based Costs

> **Note**: The OpenCost UI dropdown doesn't include a "Label" option. Use URL parameters or the API instead.

**Via URL** (opens in browser):

```text
http://<OPENCOST_IP>:9090/allocation?window=7d&agg=label:team
http://<OPENCOST_IP>:9090/allocation?window=7d&agg=label:cost-center
http://<OPENCOST_IP>:9090/allocation?window=7d&agg=label:project
```

**Via API**:

```bash
# Costs by team
curl "http://<IP>:9090/model/allocation?window=7d&aggregate=label:team"

# Costs by cost center
curl "http://<IP>:9090/model/allocation?window=7d&aggregate=label:cost-center"

# With shared costs distributed
curl "http://<IP>:9090/model/allocation?window=7d&aggregate=label:team&shareIdle=true&shareNamespaces=kube-system"
```

#### UI Dropdown Options

The OpenCost UI **Breakdown** dropdown supports these built-in aggregations:

- Cluster, Node, Namespace, Controller Kind, Controller
- DaemonSet, Deployment, Job, Service, StatefulSet, Pod, Container

For custom label aggregations, use the URL or API methods above.

### Export Allocation Data

Export Kubernetes cost allocation data to Azure Storage (like Cost Management exports):

```powershell
# Manual export (CSV)
.\export-allocation-data.ps1 -Window "7d" -Format "csv"

# Export as Parquet
.\export-allocation-data.ps1 -Window "yesterday" -Format "parquet"

# Setup automated exports via CronJob
.\setup-allocation-export.ps1 -Schedule "0 6 * * *"  # Daily at 6 AM
```

---

## Contributing

Feel free to submit issues and pull requests to improve this deployment.

## License

This project is provided as-is for demonstration purposes.
