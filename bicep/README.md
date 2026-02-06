# OpenCost on AKS - Bicep Deployment

This directory contains Bicep templates for deploying [OpenCost](https://www.opencost.io/) on Azure Kubernetes Service (AKS) with full Azure Cloud Costs integration.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Accessing OpenCost](#accessing-opencost)
- [Customization](#customization)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

## Overview

This Bicep deployment creates:

- ✅ **AKS Cluster** - Azure Kubernetes Service with managed identity
- ✅ **Prometheus** - Metrics collection for Kubernetes costs
- ✅ **OpenCost** - Real-time cost monitoring UI and API
- ✅ **Azure Cloud Costs** - Integration with Azure Cost Management
- ✅ **Storage Account** - For Azure billing data exports
- ✅ **Service Principal** - For Azure Retail Pricing API access
- ✅ **Custom RBAC Roles** - Least-privilege access for OpenCost

### What Gets Deployed

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
│  └─────────────────┘    └─────────────────┘                         │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools

| Tool | Version | Installation |
|------|---------|--------------|
| **Azure CLI** | >= 2.50 | [Install Guide](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| **kubectl** | >= 1.25 | [Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | >= 3.10 | [Install Guide](https://helm.sh/docs/intro/install/) |
| **PowerShell 7+** or **Bash** | Latest | [PowerShell](https://docs.microsoft.com/powershell/scripting/install/installing-powershell) / Bash |

### Azure RBAC Requirements

| Role | Scope | Purpose |
|------|-------|---------|
| **Contributor** | Subscription or Resource Group | Create AKS, Storage, etc. |
| **User Access Administrator** | Subscription | Create custom roles and service principals |
| **Cost Management Reader** | Subscription | Create cost exports |

### Verify Prerequisites

```bash
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

## Architecture

### Bicep Modules Structure

```
bicep/
├── main.bicep                    # Main orchestration template
├── modules/
│   ├── aks.bicep                # AKS cluster module
│   ├── opencost-role.bicep      # Custom role definition
│   ├── service-principal.bicep  # Service principal (placeholder)
│   └── cloud-costs.bicep        # Storage & cost export module
├── deploy.ps1                    # PowerShell deployment script
├── deploy.sh                     # Bash deployment script (optional)
├── parameters.json               # Deployment parameters
├── parameters.example.json       # Example parameters
└── README.md                     # This file
```

### Deployment Flow

1. **Infrastructure Deployment** (Bicep)
   - Resource Group
   - AKS Cluster with managed identity
   - Custom role definition for OpenCost
   - Storage Account with Data Lake Gen2
   - Cost Management Export

2. **Azure AD Setup** (Azure CLI in script)
   - Service Principal creation
   - Role assignment

3. **Kubernetes Deployment** (Helm in script)
   - Prometheus installation
   - OpenCost installation
   - Secrets creation

## Quick Start

### 1. Navigate to Bicep Directory

```powershell
cd bicep/
```

### 2. Configure Parameters

```powershell
# Copy example parameters file
cp parameters.example.json parameters.json

# Edit with your values (optional - defaults work fine)
notepad parameters.json  # Windows
nano parameters.json     # Linux/Mac
```

### 3. Deploy Everything

**PowerShell:**
```powershell
.\deploy.ps1
```

**Bash:**
```bash
./deploy.sh
```

The deployment takes approximately **15-20 minutes**.

### 4. Access OpenCost

Once deployed, get the LoadBalancer IP:

```bash
kubectl get service opencost -n opencost
```

Then open: `http://<EXTERNAL-IP>:9090`

## Configuration

### Parameters File

Edit `parameters.json` to customize your deployment:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "resourceGroupName": {
      "value": "rg-opencost-demo"
    },
    "location": {
      "value": "swedencentral"
    },
    "clusterName": {
      "value": "aks-opencost-demo"
    },
    "nodeCount": {
      "value": 2
    },
    "nodeVmSize": {
      "value": "Standard_D2s_v5"
    },
    "enableCloudCosts": {
      "value": true
    }
  }
}
```

### Available Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `resourceGroupName` | Resource group name | `rg-opencost-demo` |
| `location` | Azure region | `swedencentral` |
| `clusterName` | AKS cluster name | `aks-opencost-demo` |
| `nodeCount` | Number of nodes | `2` |
| `nodeVmSize` | VM size | `Standard_D2s_v5` |
| `networkPlugin` | Network plugin | `azure` |
| `networkPolicy` | Network policy | `azure` |
| `enableAutoScaling` | Enable autoscaling | `false` |
| `minNodeCount` | Min nodes (autoscaling) | `2` |
| `maxNodeCount` | Max nodes (autoscaling) | `5` |
| `enableCloudCosts` | Enable Cloud Costs | `true` |
| `tags` | Resource tags | See example |

## Deployment

### Full Deployment (Recommended)

```powershell
# PowerShell
.\deploy.ps1

# Bash
./deploy.sh
```

### Skip Azure Login

If already logged in:

```powershell
.\deploy.ps1 -SkipLogin
```

### Custom Parameters File

```powershell
.\deploy.ps1 -ParametersFile "custom-params.json"
```

### Specific Subscription

```powershell
.\deploy.ps1 -SubscriptionId "your-subscription-id"
```

### Infrastructure Only (Bicep Only)

```bash
az deployment sub create \
  --location swedencentral \
  --template-file main.bicep \
  --parameters @parameters.json
```

## Accessing OpenCost

### Method 1: LoadBalancer (Public IP)

```bash
# Get the external IP
kubectl get service opencost -n opencost

# Open in browser
# http://<EXTERNAL-IP>:9090
```

### Method 2: Port Forwarding

```bash
# Forward OpenCost ports
kubectl port-forward --namespace opencost service/opencost 9003 9090

# Access URLs:
# OpenCost UI:  http://localhost:9090
# OpenCost API: http://localhost:9003
```

### Method 3: Prometheus UI

```bash
# Forward Prometheus port
kubectl port-forward --namespace prometheus-system service/prometheus-server 9080:80

# Access Prometheus UI
# http://localhost:9080
```

## Customization

### Different Azure Region

Edit `parameters.json`:
```json
"location": {
  "value": "eastus"
}
```

### Larger Node Pool

Edit `parameters.json`:
```json
"nodeVmSize": {
  "value": "Standard_D4s_v5"
},
"nodeCount": {
  "value": 3
}
```

### Enable Auto-scaling

Edit `parameters.json`:
```json
"enableAutoScaling": {
  "value": true
},
"minNodeCount": {
  "value": 2
},
"maxNodeCount": {
  "value": 10
}
```

### Disable Cloud Costs

If you don't need Azure billing integration:

Edit `parameters.json`:
```json
"enableCloudCosts": {
  "value": false
}
```

## Outputs

The deployment outputs useful information:

| Output | Description |
|--------|-------------|
| `resourceGroupName` | Resource group name |
| `aksClusterName` | AKS cluster name |
| `servicePrincipalAppId` | Service principal app ID |
| `storageAccountName` | Storage account name |
| `subscriptionId` | Azure subscription ID |
| `tenantId` | Azure tenant ID |

## Cleanup

### Full Cleanup

```bash
# Delete resource group (removes AKS, storage, etc.)
az group delete --name rg-opencost-demo --yes --no-wait

# Delete service principal
az ad sp delete --id <service-principal-app-id>

# Delete custom role
az role definition delete --name OpenCostRole-<suffix>
```

### Using Deployment Script Output

The deployment script provides cleanup commands at the end.

## Troubleshooting

### Issue: Bicep Deployment Fails

**Problem**: `Deployment failed`

**Solution**:
```bash
# Check deployment status
az deployment sub show --name <deployment-name>

# View error details
az deployment sub show \
  --name <deployment-name> \
  --query properties.error
```

### Issue: Service Principal Creation Fails

**Problem**: `Insufficient privileges`

**Solution**:
- Ensure you have User Access Administrator role
- Or Application Administrator role in Azure AD

### Issue: OpenCost Pods Not Starting

**Problem**: Pods stuck in `Pending` or `CrashLoopBackOff`

**Solution**:
```bash
# Check pod status
kubectl get pods -n opencost
kubectl describe pod <pod-name> -n opencost

# Check logs
kubectl logs -n opencost <pod-name>
```

### Issue: LoadBalancer IP Not Assigned

**Problem**: External IP shows `<pending>`

**Solution**:
```bash
# Wait 3-5 minutes for Azure to provision
kubectl get service opencost -n opencost --watch

# Check events
kubectl describe service opencost -n opencost
```

### Issue: Cloud Costs Not Showing

**Problem**: Azure billing data not appearing

**Solution**:
1. Cost exports take 24-48 hours to generate first data
2. Check export status in Azure Portal
3. Verify storage account key in secret

### Debug Commands

```bash
# Check all pods
kubectl get pods --all-namespaces

# Check OpenCost deployment
kubectl describe deployment opencost -n opencost

# Check secrets
kubectl get secrets -n opencost

# Test OpenCost API
kubectl port-forward -n opencost service/opencost 9003:9003
curl http://localhost:9003/allocation/compute?window=1h
```

## Differences from Terraform

### What's Different?

1. **Service Principal Creation**
   - Bicep: Created via Azure CLI in deployment script
   - Terraform: Created via Terraform provider

2. **Helm Chart Deployment**
   - Bicep: Deployed via Helm CLI in script
   - Terraform: Deployed via Terraform Helm provider

3. **Secret Management**
   - Bicep: Secrets created via kubectl in script
   - Terraform: Secrets created via Terraform Kubernetes provider

### Why These Differences?

Bicep focuses on Azure resource provisioning. For Kubernetes and Azure AD resources, the deployment script handles them using appropriate CLIs, which is a common pattern in Bicep deployments.

## Best Practices

### Production Deployment

For production use:

1. **Enable Auto-scaling**
2. **Use Larger Nodes** (Standard_D4s_v5 or larger)
3. **Enable Azure Monitor**
4. **Use Private AKS Cluster**
5. **Implement Azure AD Integration**
6. **Enable Azure Policy**

### Security

1. **Store parameters file securely** (contains configuration)
2. **Rotate service principal credentials regularly**
3. **Use Azure Key Vault for secrets**
4. **Enable diagnostic logging**

### Cost Optimization

1. **Use spot instances for non-critical workloads**
2. **Enable auto-scaling** to match demand
3. **Right-size your nodes**
4. **Review cost exports regularly**

## Additional Resources

- [OpenCost Documentation](https://www.opencost.io/docs/)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure AKS Best Practices](https://learn.microsoft.com/azure/aks/best-practices)
- [Azure Cost Management](https://learn.microsoft.com/azure/cost-management-billing/)

## Comparison: Bicep vs Terraform vs PowerShell

| Aspect | Bicep | Terraform | PowerShell Scripts |
|--------|-------|-----------|-------------------|
| **Infrastructure** | ✅ Native Azure | ✅ Multi-cloud | ✅ Azure CLI |
| **K8s Resources** | ⚠️ Via script | ✅ Native provider | ✅ kubectl/helm |
| **State Management** | ✅ Azure managed | ✅ Configurable | ❌ None |
| **Learning Curve** | 🟢 Easy (Azure) | 🟡 Medium | 🟢 Easy |
| **Best For** | Azure-only | Multi-cloud | Quick demos |

## Support

For issues or questions:
- OpenCost: [GitHub Issues](https://github.com/opencost/opencost/issues)
- Azure Bicep: [GitHub Issues](https://github.com/Azure/bicep/issues)
- AKS: [Azure Support](https://azure.microsoft.com/support/)

## License

This Bicep deployment follows the same license as the parent repository.
