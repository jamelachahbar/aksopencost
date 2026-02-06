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
