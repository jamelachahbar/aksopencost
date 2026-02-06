# OpenCost Allocation Export CronJob
# Exports Kubernetes cost allocation data to Azure Storage on a schedule

# Storage Container for Allocation Exports (uses same storage account as cost exports)
resource "azurerm_storage_container" "allocation_export" {
  count = var.enable_allocation_export ? 1 : 0

  name                  = var.allocation_export_container_name
  storage_account_name  = azurerm_storage_account.cost_export[0].name
  container_access_type = "private"
}

# ConfigMap with export script
resource "kubernetes_config_map" "allocation_export_script" {
  count = var.enable_allocation_export ? 1 : 0

  metadata {
    name      = "allocation-export-script"
    namespace = kubernetes_namespace.opencost.metadata[0].name
  }

  data = {
    "export.sh" = <<-EOT
      #!/bin/sh
      set -e

      echo "============================================"
      echo "OpenCost Allocation Export"
      echo "============================================"
      echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "Window: $EXPORT_WINDOW"
      echo "Aggregate: $EXPORT_AGGREGATE"

      # Variables
      TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
      DATE_FOLDER=$(date -u +%Y/%m/%d)
      FILENAME="opencost-allocation-$TIMESTAMP.csv"
      BLOB_PATH="opencost-allocation/$DATE_FOLDER/$FILENAME"

      # Query OpenCost API
      echo ""
      echo "Step 1: Querying OpenCost allocation API..."
      OPENCOST_URL="http://opencost.opencost.svc.cluster.local:9003"
      API_URL="$OPENCOST_URL/allocation/compute?window=$EXPORT_WINDOW&aggregate=$EXPORT_AGGREGATE&accumulate=false&includeIdle=true"

      RESPONSE=$(curl -s "$API_URL")
      
      if [ -z "$RESPONSE" ]; then
        echo "ERROR: Empty response from OpenCost API"
        exit 1
      fi

      # Check for error in response
      CODE=$(echo "$RESPONSE" | jq -r '.code // 200')
      if [ "$CODE" != "200" ]; then
        echo "ERROR: API returned code $CODE"
        echo "$RESPONSE" | jq -r '.message // "Unknown error"'
        exit 1
      fi

      echo "  ✓ API query successful"

      # Transform to CSV
      echo ""
      echo "Step 2: Transforming to CSV..."

      # Create CSV header
      echo "WindowStart,WindowEnd,Name,Cluster,Namespace,ControllerKind,Controller,Pod,Container,Node,Team,Project,Environment,CostCenter,App,CPUCoreHours,CPUCoreRequestAverage,CPUCoreUsageAverage,RAMByteHours,RAMBytesRequestAverage,RAMBytesUsageAverage,CPUCost,RAMCost,GPUCost,PVCost,NetworkCost,LoadBalancerCost,SharedCost,ExternalCost,TotalCost,TotalEfficiency,ExportTimestamp" > /tmp/$FILENAME

      # Parse JSON and convert to CSV
      echo "$RESPONSE" | jq -r '
        .data[] | to_entries[] | select(.value != null) | .value |
        [
          .window.start,
          .window.end,
          .name,
          (.properties.cluster // ""),
          (.properties.namespace // ""),
          (.properties.controllerKind // ""),
          (.properties.controller // ""),
          (.properties.pod // ""),
          (.properties.container // ""),
          (.properties.node // ""),
          (.properties.labels.team // ""),
          (.properties.labels.project // ""),
          (.properties.labels.environment // ""),
          (.properties.labels."cost-center" // ""),
          (.properties.labels.app // ""),
          (.cpuCoreHours // 0),
          (.cpuCoreRequestAverage // 0),
          (.cpuCoreUsageAverage // 0),
          (.ramByteHours // 0),
          (.ramBytesRequestAverage // 0),
          (.ramBytesUsageAverage // 0),
          (.cpuCost // 0),
          (.ramCost // 0),
          (.gpuCost // 0),
          (.pvCost // 0),
          (.networkCost // 0),
          (.loadBalancerCost // 0),
          (.sharedCost // 0),
          (.externalCost // 0),
          (.totalCost // 0),
          (.totalEfficiency // 0),
          (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        ] | @csv
      ' >> /tmp/$FILENAME

      RECORD_COUNT=$(wc -l < /tmp/$FILENAME)
      RECORD_COUNT=$((RECORD_COUNT - 1))  # Subtract header
      echo "  ✓ Transformed $RECORD_COUNT records"

      # Upload to Azure Storage
      echo ""
      echo "Step 3: Uploading to Azure Storage..."
      echo "  Storage Account: $AZURE_STORAGE_ACCOUNT"
      echo "  Container: $AZURE_STORAGE_CONTAINER"
      echo "  Blob Path: $BLOB_PATH"

      # Upload using Azure Storage REST API with SAS token or access key
      az storage blob upload \
        --account-name "$AZURE_STORAGE_ACCOUNT" \
        --account-key "$AZURE_STORAGE_KEY" \
        --container-name "$AZURE_STORAGE_CONTAINER" \
        --file "/tmp/$FILENAME" \
        --name "$BLOB_PATH" \
        --overwrite \
        --output none

      echo "  ✓ Uploaded successfully"

      # Summary
      echo ""
      echo "============================================"
      echo "Export Complete!"
      echo "============================================"
      echo "  Records exported: $RECORD_COUNT"
      echo "  Blob URL: https://$AZURE_STORAGE_ACCOUNT.blob.core.windows.net/$AZURE_STORAGE_CONTAINER/$BLOB_PATH"

      # Cleanup
      rm -f /tmp/$FILENAME
    EOT
  }
}

# Secret for Storage Account Access Key
resource "kubernetes_secret" "allocation_export_storage" {
  count = var.enable_allocation_export ? 1 : 0

  metadata {
    name      = "allocation-export-storage"
    namespace = kubernetes_namespace.opencost.metadata[0].name
  }

  data = {
    storage-account-name = azurerm_storage_account.cost_export[0].name
    storage-account-key  = azurerm_storage_account.cost_export[0].primary_access_key
  }

  type = "Opaque"
}

# CronJob for Allocation Export
resource "kubernetes_cron_job_v1" "allocation_export" {
  count = var.enable_allocation_export ? 1 : 0

  metadata {
    name      = "opencost-allocation-export"
    namespace = kubernetes_namespace.opencost.metadata[0].name
    labels = {
      app = "opencost-allocation-export"
    }
  }

  spec {
    schedule                      = var.allocation_export_schedule
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        labels = {
          app = "opencost-allocation-export"
        }
      }

      spec {
        backoff_limit = 3
        
        template {
          metadata {
            labels = {
              app = "opencost-allocation-export"
            }
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = "export"
              image = "mcr.microsoft.com/azure-cli:latest"

              command = ["/bin/sh", "-c"]
              args    = ["apk add --no-cache jq curl && /scripts/export.sh"]

              env {
                name  = "EXPORT_WINDOW"
                value = var.allocation_export_window
              }

              env {
                name  = "EXPORT_AGGREGATE"
                value = var.allocation_export_aggregate
              }

              env {
                name = "AZURE_STORAGE_ACCOUNT"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.allocation_export_storage[0].metadata[0].name
                    key  = "storage-account-name"
                  }
                }
              }

              env {
                name = "AZURE_STORAGE_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.allocation_export_storage[0].metadata[0].name
                    key  = "storage-account-key"
                  }
                }
              }

              env {
                name  = "AZURE_STORAGE_CONTAINER"
                value = var.allocation_export_container_name
              }

              volume_mount {
                name       = "export-script"
                mount_path = "/scripts"
                read_only  = true
              }

              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "512Mi"
                }
              }
            }

            volume {
              name = "export-script"
              config_map {
                name         = kubernetes_config_map.allocation_export_script[0].metadata[0].name
                default_mode = "0755"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.opencost,
    azurerm_storage_container.allocation_export
  ]
}
