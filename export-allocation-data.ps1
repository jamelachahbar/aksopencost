#############################################################################
# Export OpenCost Allocation Data to Azure Storage
#
# This script queries the OpenCost allocation API and exports the data
# to Azure Blob Storage in CSV format, similar to Cost Management exports.
#
# Usage:
#   .\export-allocation-data.ps1                          # Export last 7 days
#   .\export-allocation-data.ps1 -Window "yesterday"      # Export yesterday
#   .\export-allocation-data.ps1 -Window "month"          # Export current month
#   .\export-allocation-data.ps1 -Format "parquet"        # Export as Parquet
#
# Prerequisites:
# - OpenCost running and accessible
# - Azure CLI logged in
# - For Parquet: Python with pandas and pyarrow installed
#############################################################################

param(
    [string]$OpenCostUrl = "http://20.240.180.61:9090",
    [string]$Window = "7d",
    [string]$Aggregate = "namespace,controller,pod",
    [string]$StorageAccount = "opencostexport6372",
    [string]$Container = "cost-exports",
    [string]$ResourceGroup = "rg-opencost-demo",
    [ValidateSet("csv", "parquet", "json")]
    [string]$Format = "csv",
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$dateFolder = Get-Date -Format "yyyy/MM/dd"

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost Allocation Data Export" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "  OpenCost URL: $OpenCostUrl" -ForegroundColor Gray
Write-Host "  Window: $Window" -ForegroundColor Gray
Write-Host "  Aggregate: $Aggregate" -ForegroundColor Gray
Write-Host "  Format: $Format" -ForegroundColor Gray

# ============================================================================
# Step 1: Query OpenCost Allocation API
# ============================================================================
Write-Host "`nStep 1: Querying OpenCost allocation API..." -ForegroundColor Yellow

$apiUrl = "$OpenCostUrl/model/allocation?window=$Window&aggregate=$Aggregate&accumulate=false&includeIdle=true"
Write-Host "  API URL: $apiUrl" -ForegroundColor Gray

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Get -TimeoutSec 120
    Write-Host "  ✓ API query successful" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to query OpenCost API: $_" -ForegroundColor Red
    exit 1
}

if ($response.code -ne 200) {
    Write-Host "  ✗ API returned error: $($response.message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Step 2: Transform data to flat structure
# ============================================================================
Write-Host "`nStep 2: Transforming allocation data..." -ForegroundColor Yellow

$allocationRecords = @()

foreach ($windowData in $response.data) {
    foreach ($key in $windowData.PSObject.Properties.Name) {
        $allocation = $windowData.$key
        
        # Skip if null
        if (-not $allocation) { continue }
        
        # Extract labels (for cost allocation)
        $labels = $allocation.properties.labels
        $team = if ($labels -and $labels.team) { $labels.team } else { "" }
        $project = if ($labels -and $labels.project) { $labels.project } else { "" }
        $environment = if ($labels -and $labels.environment) { $labels.environment } else { "" }
        $costCenter = if ($labels -and $labels.'cost-center') { $labels.'cost-center' } else { "" }
        $app = if ($labels -and $labels.app) { $labels.app } else { "" }
        
        $record = [PSCustomObject]@{
            # Time window
            WindowStart = $allocation.window.start
            WindowEnd = $allocation.window.end
            
            # Resource identification
            Name = $allocation.name
            Cluster = $allocation.properties.cluster
            Namespace = $allocation.properties.namespace
            ControllerKind = $allocation.properties.controllerKind
            Controller = $allocation.properties.controller
            Pod = $allocation.properties.pod
            Container = $allocation.properties.container
            Node = $allocation.properties.node
            
            # Cost Allocation Labels (for Power BI grouping)
            Team = $team
            Project = $project
            Environment = $environment
            CostCenter = $costCenter
            App = $app
            
            # Resource usage
            CPUCoreHours = [math]::Round($allocation.cpuCoreHours, 6)
            CPUCoreRequestAverage = [math]::Round($allocation.cpuCoreRequestAverage, 6)
            CPUCoreUsageAverage = [math]::Round($allocation.cpuCoreUsageAverage, 6)
            RAMByteHours = [math]::Round($allocation.ramByteHours, 2)
            RAMBytesRequestAverage = [math]::Round($allocation.ramBytesRequestAverage, 2)
            RAMBytesUsageAverage = [math]::Round($allocation.ramBytesUsageAverage, 2)
            
            # Costs
            CPUCost = [math]::Round($allocation.cpuCost, 6)
            RAMCost = [math]::Round($allocation.ramCost, 6)
            GPUCost = [math]::Round($allocation.gpuCost, 6)
            PVCost = [math]::Round($allocation.pvCost, 6)
            NetworkCost = [math]::Round($allocation.networkCost, 6)
            LoadBalancerCost = [math]::Round($allocation.loadBalancerCost, 6)
            SharedCost = [math]::Round($allocation.sharedCost, 6)
            ExternalCost = [math]::Round($allocation.externalCost, 6)
            TotalCost = [math]::Round($allocation.totalCost, 6)
            TotalEfficiency = [math]::Round($allocation.totalEfficiency, 4)
            
            # Metadata
            ExportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        
        $allocationRecords += $record
    }
}

Write-Host "  ✓ Transformed $($allocationRecords.Count) allocation records" -ForegroundColor Green

# ============================================================================
# Step 3: Export to file
# ============================================================================
Write-Host "`nStep 3: Exporting to $Format format..." -ForegroundColor Yellow

$exportDir = ".\exports"
if (-not (Test-Path $exportDir)) {
    New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
}

$baseFileName = "opencost-allocation-$timestamp"

switch ($Format) {
    "csv" {
        $localFile = "$exportDir\$baseFileName.csv"
        $allocationRecords | Export-Csv -Path $localFile -NoTypeInformation -Encoding UTF8
        Write-Host "  ✓ Exported to $localFile" -ForegroundColor Green
    }
    "json" {
        $localFile = "$exportDir\$baseFileName.json"
        $allocationRecords | ConvertTo-Json -Depth 10 | Out-File -FilePath $localFile -Encoding UTF8
        Write-Host "  ✓ Exported to $localFile" -ForegroundColor Green
    }
    "parquet" {
        $localFile = "$exportDir\$baseFileName.parquet"
        $csvTemp = "$exportDir\$baseFileName-temp.csv"
        
        # Export to CSV first, then convert to Parquet using Python
        $allocationRecords | Export-Csv -Path $csvTemp -NoTypeInformation -Encoding UTF8
        
        # Check if Python and required packages are available
        $pythonCheck = python -c "import pandas; import pyarrow" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  ⚠ Python with pandas/pyarrow not found. Installing..." -ForegroundColor Yellow
            pip install pandas pyarrow -q
        }
        
        # Convert to Parquet
        $pythonScript = @"
import pandas as pd
df = pd.read_csv('$($csvTemp -replace '\\', '/')')
df.to_parquet('$($localFile -replace '\\', '/')', engine='pyarrow', compression='snappy')
print(f'Converted {len(df)} records to Parquet')
"@
        $pythonScript | python
        
        # Clean up temp CSV
        Remove-Item $csvTemp -Force
        Write-Host "  ✓ Exported to $localFile" -ForegroundColor Green
    }
}

# ============================================================================
# Step 4: Upload to Azure Storage
# ============================================================================
if (-not $SkipUpload) {
    Write-Host "`nStep 4: Uploading to Azure Storage..." -ForegroundColor Yellow
    
    $blobPath = "opencost-allocation/$dateFolder/$baseFileName.$Format"
    Write-Host "  Storage Account: $StorageAccount" -ForegroundColor Gray
    Write-Host "  Container: $Container" -ForegroundColor Gray
    Write-Host "  Blob Path: $blobPath" -ForegroundColor Gray
    
    # Get storage key
    $storageKey = az storage account keys list -g $ResourceGroup -n $StorageAccount --query "[0].value" -o tsv
    
    # Upload file
    az storage blob upload `
        --account-name $StorageAccount `
        --account-key $storageKey `
        --container-name $Container `
        --file $localFile `
        --name $blobPath `
        --overwrite `
        --output none
    
    Write-Host "  ✓ Uploaded to Azure Storage" -ForegroundColor Green
    Write-Host "`n  Blob URL: https://$StorageAccount.blob.core.windows.net/$Container/$blobPath" -ForegroundColor Cyan
} else {
    Write-Host "`nStep 4: Skipping upload (--SkipUpload specified)" -ForegroundColor Gray
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "Export Complete!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "  Records exported: $($allocationRecords.Count)" -ForegroundColor White
Write-Host "  Local file: $localFile" -ForegroundColor White
if (-not $SkipUpload) {
    Write-Host "  Azure blob: $blobPath" -ForegroundColor White
}

# Return summary for automation
return @{
    RecordCount = $allocationRecords.Count
    LocalFile = $localFile
    BlobPath = if (-not $SkipUpload) { $blobPath } else { $null }
    Window = $Window
    Timestamp = $timestamp
}
