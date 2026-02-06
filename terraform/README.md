# OpenCost on AKS - Terraform Deployment

This directory contains Terraform configuration for deploying [OpenCost](https://www.opencost.io/) on Azure Kubernetes Service (AKS) with full Azure Cloud Costs integration.

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

This Terraform configuration deploys:

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
| **Terraform** | >= 1.5.0 | [Install Guide](https://developer.hashicorp.com/terraform/downloads) |
| **Azure CLI** | >= 2.50 | [Install Guide](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| **kubectl** | >= 1.25 | [Install Guide](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | >= 3.10 | [Install Guide](https://helm.sh/docs/intro/install/) |

### Azure RBAC Requirements

| Role | Scope | Purpose |
|------|-------|---------|
| **Contributor** | Subscription or Resource Group | Create AKS, Storage, etc. |
| **User Access Administrator** | Subscription | Create custom roles and service principals |
| **Cost Management Reader** | Subscription | Create cost exports |

### Verify Prerequisites

```bash
# Check Terraform
terraform version

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

### Terraform Modules Structure

```
terraform/
├── main.tf              # Main infrastructure resources
├── providers.tf         # Provider configurations
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── cloud-costs.tf       # Azure Cloud Costs integration
├── terraform.tfvars.example  # Example variables
├── files/
│   └── prometheus-values.yaml  # Prometheus Helm values
└── README.md            # This file
```

### Resource Dependencies

```
Resource Group
    └── AKS Cluster (Managed Identity)
        ├── Prometheus Namespace
        │   └── Prometheus Helm Release
        │
        └── OpenCost Namespace
            ├── Service Principal (Azure AD)
            │   └── Custom Role Assignment
            │
            ├── Azure Service Key Secret
            ├── Azure Storage Config Secret (if cloud costs enabled)
            │
            └── OpenCost Helm Release
                └── LoadBalancer Service

Storage Account (if cloud costs enabled)
    └── Cost Export Container
        └── Cost Management Export
```

## Quick Start

### 1. Clone and Navigate

```bash
cd terraform/
```

### 2. Configure Variables

```bash
# Copy example variables file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Plan Deployment

```bash
terraform plan
```

### 5. Deploy

```bash
terraform apply
```

The deployment takes approximately **15-20 minutes**.

### 6. Get AKS Credentials

```bash
az aks get-credentials \
  --resource-group rg-opencost-demo \
  --name aks-opencost-demo
```

### 7. Verify Deployment

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Get OpenCost LoadBalancer IP
kubectl get service opencost -n opencost
```

## Configuration

### Essential Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `resource_group_name` | Resource group name | `rg-opencost-demo` |
| `location` | Azure region | `swedencentral` |
| `cluster_name` | AKS cluster name | `aks-opencost-demo` |
| `node_count` | Number of nodes | `2` |
| `node_vm_size` | VM size for nodes | `Standard_D2s_v5` |
| `enable_cloud_costs` | Enable Azure Cloud Costs | `true` |

### Network Configuration

| Variable | Description | Options |
|----------|-------------|---------|
| `network_plugin` | Network plugin | `azure` (CNI), `kubenet` |
| `network_policy` | Network policy | `azure`, `calico`, `cilium` |

### Auto-scaling Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_auto_scaling` | Enable cluster autoscaling | `false` |
| `min_node_count` | Minimum nodes | `2` |
| `max_node_count` | Maximum nodes | `5` |

### Cloud Costs Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_cloud_costs` | Enable Cloud Costs integration | `true` |
| `storage_account_name_prefix` | Storage account prefix | `opencostexport` |
| `cost_export_name` | Cost export name | `opencost-daily` |
| `cost_export_container_name` | Container name | `cost-exports` |

## Deployment

### Standard Deployment

```bash
# Initialize
terraform init

# Plan
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

### Deployment Without Cloud Costs

If you don't need Azure billing data integration:

```bash
terraform apply -var="enable_cloud_costs=false"
```

### Deployment with Custom Variables

```bash
terraform apply \
  -var="cluster_name=my-opencost-cluster" \
  -var="location=eastus" \
  -var="node_count=3"
```

## Accessing OpenCost

### Method 1: LoadBalancer (Public IP)

```bash
# Get the external IP
kubectl get service opencost -n opencost

# Wait for EXTERNAL-IP to be assigned (may take 2-3 minutes)
# Then open in browser: http://<EXTERNAL-IP>:9090
```

### Method 2: Port Forwarding (Local Access)

```bash
# Forward OpenCost ports to localhost
kubectl port-forward --namespace opencost service/opencost 9003 9090

# Access URLs:
# OpenCost UI:  http://localhost:9090
# OpenCost API: http://localhost:9003
```

### Method 3: Prometheus UI

```bash
# Forward Prometheus port
kubectl port-forward --namespace prometheus-system service/prometheus-server 9080:80

# Access Prometheus UI: http://localhost:9080
```

## Customization

### Custom Helm Chart Versions

Edit `terraform.tfvars`:

```hcl
prometheus_version = "25.8.0"  # Update to desired version
opencost_version   = "1.26.0"  # Update to desired version
```

### Custom Node Pool

Edit `terraform.tfvars`:

```hcl
node_vm_size = "Standard_D4s_v5"  # Larger nodes
node_count   = 3                   # More nodes
```

### Enable Auto-scaling

Edit `terraform.tfvars`:

```hcl
enable_auto_scaling = true
min_node_count      = 2
max_node_count      = 10
```

### Custom Tags

Edit `terraform.tfvars`:

```hcl
tags = {
  Environment = "Production"
  ManagedBy   = "Terraform"
  Purpose     = "OpenCost"
  Owner       = "FinOps Team"
  CostCenter  = "CC-1001"
}
```

## Outputs

After deployment, Terraform outputs useful information:

```bash
# View all outputs
terraform output

# View specific output
terraform output opencost_url

# Get kubeconfig (sensitive)
terraform output -raw aks_kube_config > kubeconfig.yaml
```

### Available Outputs

| Output | Description |
|--------|-------------|
| `resource_group_name` | Resource group name |
| `aks_cluster_name` | AKS cluster name |
| `opencost_service_principal_app_id` | Service principal app ID |
| `storage_account_name` | Storage account name |
| `opencost_url` | Command to get OpenCost URL |
| `get_credentials_command` | Command to get AKS credentials |
| `port_forward_commands` | Port forwarding commands |

## Cleanup

### Destroy All Resources

```bash
# Destroy everything
terraform destroy

# Destroy with auto-approve (no confirmation)
terraform destroy -auto-approve
```

### Destroy Specific Resources

```bash
# Destroy only cloud costs resources
terraform destroy -target=azurerm_storage_account.cost_export

# Destroy only AKS cluster
terraform destroy -target=azurerm_kubernetes_cluster.aks
```

## Troubleshooting

### Issue: Terraform State Lock

**Problem**: `Error acquiring the state lock`

**Solution**:
```bash
# Force unlock (use carefully)
terraform force-unlock <LOCK_ID>
```

### Issue: Insufficient Permissions

**Problem**: `Authorization failed`

**Solution**:
- Ensure you have Contributor + User Access Administrator roles
- Check with: `az role assignment list --assignee $(az account show --query user.name -o tsv)`

### Issue: OpenCost Pods Not Starting

**Problem**: Pods stuck in `Pending` or `CrashLoopBackOff`

**Solution**:
```bash
# Check pod status
kubectl get pods -n opencost
kubectl describe pod <pod-name> -n opencost

# Check logs
kubectl logs -n opencost <pod-name>

# Check events
kubectl get events -n opencost --sort-by='.lastTimestamp'
```

### Issue: LoadBalancer IP Not Assigned

**Problem**: Service shows `<pending>` for EXTERNAL-IP

**Solution**:
```bash
# Check service
kubectl describe service opencost -n opencost

# Wait up to 5 minutes for Azure to provision the LoadBalancer
# If still pending, check Azure resource group for NSG/LB issues
```

### Issue: Cloud Costs Not Showing

**Problem**: Azure billing data not appearing in OpenCost

**Solution**:
1. Cost exports take 24-48 hours to generate first data
2. Check export status:
   ```bash
   az costmanagement export show \
     --name opencost-daily \
     --scope /subscriptions/<subscription-id>/resourceGroups/rg-opencost-demo
   ```
3. Verify storage account access:
   ```bash
   kubectl get secret azure-storage-config -n opencost -o yaml
   ```

### Debug Commands

```bash
# Check all resources
kubectl get all --all-namespaces

# Check OpenCost configuration
kubectl describe deployment opencost -n opencost

# Check Prometheus configuration
kubectl describe deployment prometheus-server -n prometheus-system

# Check secrets
kubectl get secrets -n opencost

# Test OpenCost API
kubectl port-forward -n opencost service/opencost 9003:9003
curl http://localhost:9003/allocation/compute?window=1h
```

## Best Practices

### Production Deployment

For production use, consider:

1. **Enable Auto-scaling**:
   ```hcl
   enable_auto_scaling = true
   min_node_count      = 3
   max_node_count      = 10
   ```

2. **Use Larger Nodes**:
   ```hcl
   node_vm_size = "Standard_D4s_v5"  # 4 vCPU, 16 GB RAM
   ```

3. **Enable Azure Monitor**:
   - Add container insights
   - Enable diagnostic settings

4. **Secure Access**:
   - Use private AKS cluster
   - Implement Azure AD integration
   - Use Azure Policy for governance

5. **Backup State**:
   - Use remote backend (Azure Storage)
   - Enable state locking

### Remote State Configuration

Create `backend.tf`:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "tfstate<unique>"
    container_name       = "tfstate"
    key                  = "opencost.terraform.tfstate"
  }
}
```

## Additional Resources

- [OpenCost Documentation](https://www.opencost.io/docs/)
- [Azure AKS Best Practices](https://learn.microsoft.com/azure/aks/best-practices)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Cost Management](https://learn.microsoft.com/azure/cost-management-billing/)

## Support

For issues or questions:
- OpenCost: [GitHub Issues](https://github.com/opencost/opencost/issues)
- AKS: [Azure Support](https://azure.microsoft.com/support/)
- Terraform: [Community Forum](https://discuss.hashicorp.com/c/terraform-core/)

## License

This Terraform configuration follows the same license as the parent repository.
