# Storage Account for Cost Exports
resource "azurerm_storage_account" "cost_export" {
  count = var.enable_cloud_costs ? 1 : 0

  name                     = "${var.storage_account_name_prefix}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Data Lake Gen2
  shared_access_key_enabled = true

  tags = merge(var.tags, {
    SecurityControl = "ignore" # Bypass policy that blocks shared key access
  })
}

# Storage Container for Cost Exports
resource "azurerm_storage_container" "cost_export" {
  count = var.enable_cloud_costs ? 1 : 0

  name                  = var.cost_export_container_name
  storage_account_name  = azurerm_storage_account.cost_export[0].name
  container_access_type = "private"
}

# Cost Management Export
resource "azurerm_cost_management_export_resource_group" "opencost" {
  count = var.enable_cloud_costs ? 1 : 0

  name                    = var.cost_export_name
  resource_group_id       = azurerm_resource_group.rg.id
  recurrence_type         = "Daily"
  recurrence_period_start = "${formatdate("YYYY-MM-DD", timestamp())}T00:00:00Z"
  recurrence_period_end   = "${formatdate("YYYY-MM-DD", timeadd(timestamp(), "8760h"))}T00:00:00Z" # 1 year from now

  export_data_storage_location {
    container_id     = azurerm_storage_container.cost_export[0].resource_manager_id
    root_folder_path = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
  }

  export_data_options {
    type       = "ActualCost"
    time_frame = "MonthToDate"
  }

  depends_on = [
    azurerm_storage_container.cost_export
  ]
}

# Role Assignment for Cost Management Reader (for Cost Export)
resource "azurerm_role_assignment" "cost_management_reader" {
  count = var.enable_cloud_costs ? 1 : 0

  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Kubernetes Secret for Azure Storage Access (Cloud Costs)
resource "kubernetes_secret" "azure_storage_config" {
  count = var.enable_cloud_costs ? 1 : 0

  metadata {
    name      = "azure-storage-config"
    namespace = kubernetes_namespace.opencost.metadata[0].name
  }

  data = {
    "azure-storage-config.json" = jsonencode({
      azureStorageAccount   = azurerm_storage_account.cost_export[0].name
      azureStorageAccessKey = azurerm_storage_account.cost_export[0].primary_access_key
      azureStorageContainer = var.cost_export_container_name
      azureContainerPath    = "/subscriptions/${data.azurerm_subscription.current.subscription_id}"
      azureCloud            = "public"
    })
  }

  type = "Opaque"

  depends_on = [
    azurerm_storage_account.cost_export,
    kubernetes_namespace.opencost
  ]
}
