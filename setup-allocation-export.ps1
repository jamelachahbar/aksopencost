#############################################################################
# Deploy OpenCost Allocation Export CronJob
#
# This script deploys a Kubernetes CronJob that automatically exports
# OpenCost allocation data to Azure Storage on a schedule.
#
# Usage:
#   .\setup-allocation-export.ps1                     # Deploy with defaults
#   .\setup-allocation-export.ps1 -Schedule "0 6 * * *"  # Daily at 6 AM UTC
#   .\setup-allocation-export.ps1 -Format parquet     # Export as Parquet
#
# Prerequisites:
# - OpenCost running in the cluster
# - Storage account with container created
#############################################################################

param(
    [string]$StorageAccount = "opencostexport6372",
    [string]$Container = "cost-exports",
    [string]$ResourceGroup = "rg-opencost-demo",
    [string]$Schedule = "0 */6 * * *",  # Every 6 hours
    [ValidateSet("csv", "parquet", "json")]
    [string]$Format = "csv",
    [string]$Window = "yesterday",
    [string]$Aggregate = "namespace,controller"
)

$ErrorActionPreference = "Stop"
$SUBSCRIPTION_ID = az account show --query id -o tsv

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "OpenCost Allocation Export - CronJob Setup" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "  Schedule: $Schedule (cron format)" -ForegroundColor Gray
Write-Host "  Format: $Format" -ForegroundColor Gray
Write-Host "  Window: $Window" -ForegroundColor Gray
Write-Host "  Storage: $StorageAccount/$Container" -ForegroundColor Gray

# ============================================================================
# Step 1: Get Storage Account Key
# ============================================================================
Write-Host "`nStep 1: Getting storage account key..." -ForegroundColor Yellow

$storageKey = az storage account keys list -g $ResourceGroup -n $StorageAccount --query "[0].value" -o tsv
Write-Host "  ✓ Retrieved storage key" -ForegroundColor Green

# ============================================================================
# Step 2: Create Secret for Storage Credentials
# ============================================================================
Write-Host "`nStep 2: Creating storage credentials secret..." -ForegroundColor Yellow

kubectl delete secret allocation-export-storage -n opencost 2>$null
kubectl create secret generic allocation-export-storage `
    -n opencost `
    --from-literal=AZURE_STORAGE_ACCOUNT=$StorageAccount `
    --from-literal=AZURE_STORAGE_KEY=$storageKey `
    --from-literal=AZURE_STORAGE_CONTAINER=$Container

Write-Host "  ✓ Secret created" -ForegroundColor Green

# ============================================================================
# Step 3: Create ConfigMap with Export Script
# ============================================================================
Write-Host "`nStep 3: Creating export script ConfigMap..." -ForegroundColor Yellow

$exportScript = @'
#!/bin/sh
set -e

echo "=========================================="
echo "OpenCost Allocation Export"
echo "=========================================="
echo "Time: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Window: $EXPORT_WINDOW"
echo "Aggregate: $EXPORT_AGGREGATE"
echo "Format: $EXPORT_FORMAT"

# Query OpenCost API
OPENCOST_URL="http://opencost.opencost.svc.cluster.local:9090"
API_URL="${OPENCOST_URL}/model/allocation?window=${EXPORT_WINDOW}&aggregate=${EXPORT_AGGREGATE}&accumulate=true&includeIdle=true"

echo ""
echo "Querying OpenCost API..."
RESPONSE=$(curl -s "$API_URL")

# Check response
if echo "$RESPONSE" | grep -q '"code":200'; then
    echo "✓ API query successful"
else
    echo "✗ API query failed"
    echo "$RESPONSE"
    exit 1
fi

# Create output directory
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
DATE_PATH=$(date -u +%Y/%m/%d)
OUTPUT_DIR="/tmp/export"
mkdir -p "$OUTPUT_DIR"

# Convert JSON to CSV using jq
echo ""
echo "Converting to CSV..."

# Extract allocation data and convert to CSV (including labels for Power BI)
echo "$RESPONSE" | jq -r '
    .data[] | to_entries[] | .value | select(. != null) |
    [
        .window.start,
        .window.end,
        .name,
        .properties.cluster,
        .properties.namespace,
        .properties.controllerKind,
        .properties.controller,
        .properties.pod,
        .properties.node,
        (.properties.labels.team // ""),
        (.properties.labels.project // ""),
        (.properties.labels.environment // ""),
        (.properties.labels."cost-center" // ""),
        (.properties.labels.app // ""),
        (.cpuCoreHours // 0 | tostring),
        (.cpuCoreRequestAverage // 0 | tostring),
        (.cpuCoreUsageAverage // 0 | tostring),
        (.ramByteHours // 0 | tostring),
        (.ramBytesRequestAverage // 0 | tostring),
        (.ramBytesUsageAverage // 0 | tostring),
        (.cpuCost // 0 | tostring),
        (.ramCost // 0 | tostring),
        (.gpuCost // 0 | tostring),
        (.pvCost // 0 | tostring),
        (.networkCost // 0 | tostring),
        (.loadBalancerCost // 0 | tostring),
        (.sharedCost // 0 | tostring),
        (.externalCost // 0 | tostring),
        (.totalCost // 0 | tostring),
        (.totalEfficiency // 0 | tostring)
    ] | @csv
' > "$OUTPUT_DIR/data.csv"

# Add header (including cost allocation labels)
HEADER="WindowStart,WindowEnd,Name,Cluster,Namespace,ControllerKind,Controller,Pod,Node,Team,Project,Environment,CostCenter,App,CPUCoreHours,CPUCoreRequestAverage,CPUCoreUsageAverage,RAMByteHours,RAMBytesRequestAverage,RAMBytesUsageAverage,CPUCost,RAMCost,GPUCost,PVCost,NetworkCost,LoadBalancerCost,SharedCost,ExternalCost,TotalCost,TotalEfficiency"

FINAL_FILE="$OUTPUT_DIR/opencost-allocation-${TIMESTAMP}.csv"
echo "$HEADER" > "$FINAL_FILE"
cat "$OUTPUT_DIR/data.csv" >> "$FINAL_FILE"

RECORD_COUNT=$(wc -l < "$OUTPUT_DIR/data.csv")
echo "✓ Converted $RECORD_COUNT records"

# Upload to Azure Storage
echo ""
echo "Uploading to Azure Storage..."
BLOB_PATH="opencost-allocation/${DATE_PATH}/opencost-allocation-${TIMESTAMP}.csv"

# Use azcopy or az CLI
az storage blob upload \
    --account-name "$AZURE_STORAGE_ACCOUNT" \
    --account-key "$AZURE_STORAGE_KEY" \
    --container-name "$AZURE_STORAGE_CONTAINER" \
    --file "$FINAL_FILE" \
    --name "$BLOB_PATH" \
    --overwrite \
    --only-show-errors

echo "✓ Uploaded to: $BLOB_PATH"

echo ""
echo "=========================================="
echo "Export Complete!"
echo "=========================================="
echo "Records: $RECORD_COUNT"
echo "Blob: https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${AZURE_STORAGE_CONTAINER}/${BLOB_PATH}"
'@

# Create ConfigMap
kubectl delete configmap allocation-export-script -n opencost 2>$null
kubectl create configmap allocation-export-script `
    -n opencost `
    --from-literal=export.sh=$exportScript

Write-Host "  ✓ ConfigMap created" -ForegroundColor Green

# ============================================================================
# Step 4: Deploy CronJob
# ============================================================================
Write-Host "`nStep 4: Deploying CronJob..." -ForegroundColor Yellow

$cronJobYaml = @"
apiVersion: batch/v1
kind: CronJob
metadata:
  name: opencost-allocation-export
  namespace: opencost
  labels:
    app: opencost-allocation-export
spec:
  schedule: "$Schedule"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: exporter
            image: mcr.microsoft.com/azure-cli:latest
            command: ["/bin/sh", "/scripts/export.sh"]
            env:
            - name: EXPORT_WINDOW
              value: "$Window"
            - name: EXPORT_AGGREGATE
              value: "$Aggregate"
            - name: EXPORT_FORMAT
              value: "$Format"
            - name: AZURE_STORAGE_ACCOUNT
              valueFrom:
                secretKeyRef:
                  name: allocation-export-storage
                  key: AZURE_STORAGE_ACCOUNT
            - name: AZURE_STORAGE_KEY
              valueFrom:
                secretKeyRef:
                  name: allocation-export-storage
                  key: AZURE_STORAGE_KEY
            - name: AZURE_STORAGE_CONTAINER
              valueFrom:
                secretKeyRef:
                  name: allocation-export-storage
                  key: AZURE_STORAGE_CONTAINER
            volumeMounts:
            - name: script
              mountPath: /scripts
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: 500m
                memory: 512Mi
          volumes:
          - name: script
            configMap:
              name: allocation-export-script
              defaultMode: 0755
"@

$cronJobYaml | kubectl apply -f -

Write-Host "  ✓ CronJob deployed" -ForegroundColor Green

# ============================================================================
# Step 5: Run initial export (optional)
# ============================================================================
Write-Host "`nStep 5: Running initial export job..." -ForegroundColor Yellow

# Create a one-time job from the CronJob
kubectl create job --from=cronjob/opencost-allocation-export opencost-export-initial -n opencost 2>$null

Write-Host "  ✓ Initial export job created" -ForegroundColor Green
Write-Host "  Waiting for job to complete..." -ForegroundColor Gray

# Wait for job to complete
kubectl wait --for=condition=complete job/opencost-export-initial -n opencost --timeout=300s 2>$null

# Show job logs
Write-Host "`n  Job output:" -ForegroundColor Cyan
kubectl logs job/opencost-export-initial -n opencost 2>$null | Select-Object -Last 15

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n============================================================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "CronJob Schedule: $Schedule" -ForegroundColor White
Write-Host "  - Every 6 hours: 0 */6 * * *" -ForegroundColor Gray
Write-Host "  - Daily at 6 AM: 0 6 * * *" -ForegroundColor Gray
Write-Host "  - Hourly: 0 * * * *" -ForegroundColor Gray
Write-Host ""
Write-Host "Useful Commands:" -ForegroundColor Yellow
Write-Host "  # Check CronJob status" -ForegroundColor Gray
Write-Host "  kubectl get cronjob opencost-allocation-export -n opencost" -ForegroundColor White
Write-Host ""
Write-Host "  # Manually trigger an export" -ForegroundColor Gray
Write-Host "  kubectl create job --from=cronjob/opencost-allocation-export manual-export -n opencost" -ForegroundColor White
Write-Host ""
Write-Host "  # View export logs" -ForegroundColor Gray
Write-Host "  kubectl logs -l job-name=opencost-allocation-export -n opencost" -ForegroundColor White
Write-Host ""
Write-Host "  # List exported files in storage" -ForegroundColor Gray
Write-Host "  az storage blob list --account-name $StorageAccount --container-name $Container --prefix opencost-allocation/ --query `"[].name`" -o table" -ForegroundColor White
