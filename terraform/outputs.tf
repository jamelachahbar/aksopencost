output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.id
}

output "aks_kube_config" {
  description = "Kubernetes configuration for the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive   = true
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "opencost_service_principal_app_id" {
  description = "Application ID of the OpenCost service principal"
  value       = azuread_application.opencost.client_id
}

output "opencost_service_principal_object_id" {
  description = "Object ID of the OpenCost service principal"
  value       = azuread_service_principal.opencost.object_id
}

output "subscription_id" {
  description = "Azure subscription ID"
  value       = data.azurerm_subscription.current.subscription_id
}

output "tenant_id" {
  description = "Azure tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "storage_account_name" {
  description = "Name of the storage account for cost exports"
  value       = var.enable_cloud_costs ? azurerm_storage_account.cost_export[0].name : null
}

output "cost_export_container_name" {
  description = "Name of the storage container for cost exports"
  value       = var.enable_cloud_costs ? var.cost_export_container_name : null
}

output "opencost_url" {
  description = "URL to access OpenCost (available after LoadBalancer gets an IP)"
  value       = "Run: kubectl get service opencost -n opencost -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "get_credentials_command" {
  description = "Command to get AKS credentials"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "port_forward_commands" {
  description = "Commands to port-forward to OpenCost and Prometheus"
  value = {
    opencost   = "kubectl port-forward --namespace opencost service/opencost 9003 9090"
    prometheus = "kubectl port-forward --namespace prometheus-system service/prometheus-server 9080:80"
  }
}

# Allocation Export Outputs
output "allocation_export_container_name" {
  description = "Name of the storage container for allocation exports"
  value       = var.enable_allocation_export ? var.allocation_export_container_name : null
}

output "allocation_export_schedule" {
  description = "Cron schedule for allocation exports"
  value       = var.enable_allocation_export ? var.allocation_export_schedule : null
}

output "allocation_export_cronjob_commands" {
  description = "Commands to manage the allocation export CronJob"
  value = var.enable_allocation_export ? {
    check_status   = "kubectl get cronjob opencost-allocation-export -n opencost"
    list_jobs      = "kubectl get jobs -n opencost -l app=opencost-allocation-export"
    view_logs      = "kubectl logs -n opencost -l app=opencost-allocation-export --tail=100"
    trigger_manual = "kubectl create job --from=cronjob/opencost-allocation-export manual-export-$(date +%s) -n opencost"
  } : null
}

# Sample Applications Outputs
output "sample_apps_deployed" {
  description = "Sample applications deployed for cost allocation demo"
  value = var.deploy_sample_apps ? {
    namespace = "sample-app"
    apps = {
      "api-service"    = { team = "backend", cost_center = "CC-2001", replicas = 3 }
      "web-frontend"   = { team = "frontend", cost_center = "CC-2002", replicas = 2 }
      "data-processor" = { team = "data", cost_center = "CC-3001", replicas = 2 }
      "ml-training"    = { team = "ml-engineering", cost_center = "CC-4001", replicas = 1 }
      "shared-cache"   = { team = "platform", cost_center = "CC-1001", replicas = 2 }
    }
  } : null
}

output "cost_allocation_queries" {
  description = "Example API queries for cost allocation"
  value = {
    by_cost_center = "/allocation/compute?window=7d&aggregate=label:cost-center"
    by_team        = "/allocation/compute?window=7d&aggregate=label:team"
    by_project     = "/allocation/compute?window=7d&aggregate=label:project"
    by_environment = "/allocation/compute?window=7d&aggregate=label:environment"
    multi_label    = "/allocation/compute?window=7d&aggregate=label:cost-center,label:team"
  }
}
