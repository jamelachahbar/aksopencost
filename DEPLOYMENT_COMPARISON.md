# Deployment Methods Comparison

This document provides a detailed comparison of the three deployment methods available for OpenCost on AKS.

## Overview

All three methods deploy the **exact same infrastructure** with full parity:

| Component | PowerShell | Terraform | Bicep |
|-----------|------------|-----------|-------|
| AKS Cluster | ✅ | ✅ | ✅ |
| Prometheus | ✅ | ✅ | ✅ |
| OpenCost | ✅ | ✅ | ✅ |
| Service Principal | ✅ | ✅ | ✅ |
| Custom RBAC Role | ✅ | ✅ | ✅ |
| Storage Account | ✅ | ✅ | ✅ |
| Cost Export | ✅ | ✅ | ✅ |
| Kubernetes Secrets | ✅ | ✅ | ✅ |
| Sample Apps | ✅ | ✅ | ✅ |

## Detailed Comparison

### PowerShell Scripts

**Location**: Root directory

**Pros:**
- ✅ **Quick to deploy** - Single command deployment
- ✅ **Easy to understand** - Sequential script execution
- ✅ **Great for learning** - Step-by-step process visible
- ✅ **Minimal prerequisites** - Just Azure CLI, Helm, kubectl
- ✅ **Detailed output** - Shows progress at each step
- ✅ **Interactive** - Can modify during execution

**Cons:**
- ❌ No state management
- ❌ Not declarative
- ❌ Limited idempotency
- ❌ Manual dependency management
- ❌ Not ideal for production
- ❌ Requires PowerShell 7+

**Best For:**
- Quick demos and POCs
- Learning OpenCost
- One-time deployments
- Development environments

**Deployment Time:** ~15 minutes

### Terraform

**Location**: `terraform/` directory

**Pros:**
- ✅ **Declarative IaC** - Infrastructure as Code
- ✅ **State management** - Tracks resource state
- ✅ **Multi-cloud** - Works with AWS, GCP, etc.
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Plan before apply** - Preview changes
- ✅ **Module ecosystem** - Reusable components
- ✅ **GitOps friendly** - Version control integration
- ✅ **Drift detection** - Identifies manual changes

**Cons:**
- ⚠️ Requires Terraform installation
- ⚠️ Learning curve for HCL syntax
- ⚠️ State file management needed
- ⚠️ Provider version dependencies

**Best For:**
- Production deployments
- Multi-cloud strategies
- GitOps workflows
- Teams already using Terraform
- Infrastructure automation

**Deployment Time:** ~20 minutes

**Key Features:**
- State backend configuration
- Input variables with validation
- Output values for integration
- Conditional resource creation
- Comprehensive provider support

### Bicep

**Location**: `bicep/` directory

**Pros:**
- ✅ **Azure-native** - First-class Azure support
- ✅ **Declarative IaC** - Infrastructure as Code
- ✅ **State managed by Azure** - No external state files
- ✅ **Type safety** - Strong typing and validation
- ✅ **Decompilation** - Convert from ARM templates
- ✅ **VS Code integration** - IntelliSense support
- ✅ **Idempotent** - Safe to run multiple times
- ✅ **Enterprise ready** - Azure best practices

**Cons:**
- ⚠️ Azure-only (no multi-cloud)
- ⚠️ Requires Azure CLI
- ⚠️ Learning curve for syntax
- ⚠️ Some resources need CLI (Service Principal)

**Best For:**
- Azure-centric organizations
- Enterprise Azure deployments
- Azure governance requirements
- Teams familiar with ARM templates
- Long-term Azure strategy

**Deployment Time:** ~20 minutes

**Key Features:**
- Modular structure
- Parameter files for configuration
- Azure Policy integration
- Built-in validation
- Native Azure resource support

## Feature Comparison

### State Management

| Method | State Storage | Drift Detection | Multi-User |
|--------|---------------|-----------------|------------|
| PowerShell | None | ❌ | ❌ |
| Terraform | Local/Remote | ✅ | ✅ |
| Bicep | Azure-managed | ✅ | ✅ |

### Deployment Process

| Method | Preview Changes | Rollback | Versioning |
|--------|----------------|----------|------------|
| PowerShell | ❌ | ❌ | Git only |
| Terraform | ✅ (plan) | ✅ | Git + State |
| Bicep | ✅ (what-if) | ✅ | Git + Azure |

### Developer Experience

| Method | IDE Support | Syntax Highlighting | Auto-completion |
|--------|-------------|---------------------|-----------------|
| PowerShell | VS Code | ✅ | ⚠️ Limited |
| Terraform | VS Code, IntelliJ | ✅ | ✅ |
| Bicep | VS Code | ✅ | ✅ |

### Enterprise Features

| Feature | PowerShell | Terraform | Bicep |
|---------|------------|-----------|-------|
| **RBAC Integration** | Manual | ✅ | ✅ |
| **Policy Enforcement** | Manual | ⚠️ External | ✅ Native |
| **Audit Logging** | Azure only | ✅ | ✅ |
| **Secret Management** | Manual | ✅ Vault | ✅ KeyVault |
| **CI/CD Integration** | ✅ | ✅ | ✅ |

## Resource Deployment Breakdown

### AKS Cluster Configuration

All methods deploy identical AKS configuration:
- **Network Plugin**: Azure CNI (configurable)
- **Network Policy**: Azure (configurable)
- **Identity**: System-assigned managed identity
- **Node Pool**: 2 nodes (configurable)
- **VM Size**: Standard_D2s_v5 (configurable)
- **Kubernetes Version**: Latest stable (configurable)

### Service Principal

| Method | Creation | Credentials | Rotation |
|--------|----------|-------------|----------|
| PowerShell | Azure CLI | Stored in secret | Manual |
| Terraform | Terraform | Stored in secret | Terraform |
| Bicep | CLI (script) | Stored in secret | Manual |

### Cloud Costs Integration

All methods implement the same cloud costs setup:
- Storage Account with Data Lake Gen2
- Cost Management Export (ActualCost dataset)
- Kubernetes secrets for storage access
- OpenCost environment configuration

## When to Use Each Method

### Use PowerShell Scripts When:
- ⭐ Running a quick demo or POC
- ⭐ Learning OpenCost for the first time
- ⭐ Need to deploy and test quickly
- ⭐ Working on a one-time deployment
- ⭐ Don't need state management

### Use Terraform When:
- ⭐ Building production infrastructure
- ⭐ Using multi-cloud strategy
- ⭐ Team already knows Terraform
- ⭐ Need cross-cloud consistency
- ⭐ Require advanced state management
- ⭐ Implementing GitOps workflows

### Use Bicep When:
- ⭐ Azure-only deployment
- ⭐ Enterprise Azure governance required
- ⭐ Team familiar with ARM templates
- ⭐ Want native Azure integration
- ⭐ Need Azure Policy enforcement
- ⭐ Long-term Azure commitment

## Migration Paths

### From PowerShell to IaC

1. Choose Terraform or Bicep
2. Import existing resources (if any)
3. Test in non-production
4. Switch to IaC for new deployments

### From Terraform to Bicep (or vice versa)

1. Deploy new environment with target IaC
2. Migrate workloads
3. Decommission old environment
4. Not recommended for in-place migration

## Getting Started

### PowerShell
```powershell
.\deploy-all.ps1
```

### Terraform
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Bicep
```powershell
cd bicep/
.\deploy.ps1
```

## Support and Documentation

- **PowerShell**: See main [README.md](../README.md)
- **Terraform**: See [terraform/README.md](../terraform/README.md)
- **Bicep**: See [bicep/README.md](../bicep/README.md)

## Contributing

When contributing:
- Maintain parity across all three methods
- Update all relevant documentation
- Test changes in each deployment method
- Follow existing code style
