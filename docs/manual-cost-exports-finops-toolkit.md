# Manual Cost Exports Using FinOps Toolkit for OpenCost

This guide shows how to create and manage Azure Cost Management exports using the FinOps Toolkit PowerShell module, compatible with OpenCost.

## Prerequisites

- Azure subscription with Cost Management access
- PowerShell 7.0+
- Azure CLI or Az PowerShell module (authenticated)

## Step 1: Install FinOps Toolkit Module

```powershell
Install-Module -Name FinOpsToolkit -Scope CurrentUser -Force
```

Verify installation:
```powershell
Get-Module -Name FinOpsToolkit -ListAvailable
```

## Step 2: Create Cost Export

OpenCost requires **ActualCost** dataset type with the standard schema:

```powershell
New-FinOpsCostExport `
  -Name "opencost-daily" `
  -Scope "subscriptions/<your-subscription-id>" `
  -StorageAccountId "/subscriptions/<your-subscription-id>/resourceGroups/<your-rg>/providers/Microsoft.Storage/storageAccounts/<your-storage-account>" `
  -StorageContainer "cost-exports" `
  -DatasetType "ActualCost" `
  -SchemaVersion "2021-10-01"
```

### Example with Real Values

```powershell
New-FinOpsCostExport `
  -Name "opencost-daily" `
  -Scope "subscriptions/e9b4640d-1f1f-45fe-a543-c0ea45ac34c1" `
  -StorageAccountId "/subscriptions/e9b4640d-1f1f-45fe-a543-c0ea45ac34c1/resourceGroups/rg-opencost-demo-tf/providers/Microsoft.Storage/storageAccounts/opencostexporta95k" `
  -StorageContainer "cost-exports" `
  -DatasetType "ActualCost" `
  -SchemaVersion "2021-10-01"
```

## Step 3: Run Export Manually

Trigger an immediate export:

```powershell
Start-FinOpsCostExport `
  -Name "opencost-daily" `
  -Scope "subscriptions/<your-subscription-id>"
```

## Step 4: Verify Export

Check export status and configuration:

```powershell
Get-FinOpsCostExport `
  -Name "opencost-daily" `
  -Scope "subscriptions/<your-subscription-id>"
```

List all exports in a subscription:

```powershell
Get-FinOpsCostExport -Scope "subscriptions/<your-subscription-id>"
```

## Step 5: Verify Data in Storage

Check that export data landed in storage:

```powershell
# Using Azure CLI
az storage blob list `
  --account-name <your-storage-account> `
  --container-name cost-exports `
  --auth-mode key `
  -o table

# Using Azure PowerShell
Get-AzStorageBlob `
  -Container "cost-exports" `
  -Context (Get-AzStorageAccount -ResourceGroupName <your-rg> -Name <your-storage-account>).Context
```

## OpenCost Compatibility Requirements

| Parameter | Required Value | Notes |
|-----------|----------------|-------|
| `DatasetType` | `ActualCost` | OpenCost does not support FocusCost format |
| `SchemaVersion` | `2021-10-01` | Standard schema OpenCost can parse |
| `StorageContainer` | Any | Must match OpenCost cloud-integration.json |

## Useful Commands Reference

| Command | Description |
|---------|-------------|
| `New-FinOpsCostExport` | Create a new cost export |
| `Get-FinOpsCostExport` | Get export details |
| `Start-FinOpsCostExport` | Trigger manual export run |
| `Remove-FinOpsCostExport` | Delete an export |

## Troubleshooting

### Export Not Appearing in OpenCost

1. Verify the storage path matches `cloud-integration.json`:
   ```powershell
   kubectl get secret cloud-costs -n opencost -o jsonpath='{.data.cloud-integration\.json}' | 
     % { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) } | ConvertFrom-Json
   ```

2. Check OpenCost logs for ingestion errors:
   ```powershell
   kubectl logs -n opencost deploy/opencost | Select-String -Pattern "Azure|storage|error"
   ```

3. Ensure export path structure is:
   ```
   /<container>/subscriptions/<sub-id>/<export-name>/<date-range>/<export-file>.csv
   ```

### Permission Errors

Ensure your identity has these roles:
- **Cost Management Contributor** - To create/manage exports
- **Storage Blob Data Contributor** - To write export data

## Links

- [FinOps Toolkit Documentation](https://aka.ms/finops/toolkit)
- [FinOps Toolkit PowerShell Reference](https://aka.ms/finops/powershell)
- [OpenCost Azure Integration](https://www.opencost.io/docs/configuration/azure)
