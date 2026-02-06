variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-opencost-demo"
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "swedencentral"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-opencost-demo"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "Size of the VMs in the default node pool"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster"
  type        = string
  default     = null # Use latest stable version
}

variable "network_plugin" {
  description = "Network plugin for AKS (azure or kubenet)"
  type        = string
  default     = "azure"
}

variable "network_policy" {
  description = "Network policy for AKS"
  type        = string
  default     = "azure"
}

variable "enable_auto_scaling" {
  description = "Enable auto-scaling for the default node pool"
  type        = bool
  default     = false
}

variable "min_node_count" {
  description = "Minimum number of nodes when auto-scaling is enabled"
  type        = number
  default     = 2
}

variable "max_node_count" {
  description = "Maximum number of nodes when auto-scaling is enabled"
  type        = number
  default     = 5
}

variable "storage_account_name_prefix" {
  description = "Prefix for the storage account name (will be appended with random string)"
  type        = string
  default     = "opencostexport"
}

variable "cost_export_name" {
  description = "Name of the cost export"
  type        = string
  default     = "opencost-daily"
}

variable "cost_export_container_name" {
  description = "Name of the storage container for cost exports"
  type        = string
  default     = "cost-exports"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Demo"
    ManagedBy   = "Terraform"
    Purpose     = "OpenCost"
  }
}

variable "enable_cloud_costs" {
  description = "Enable Azure Cloud Costs integration"
  type        = bool
  default     = true
}

variable "prometheus_version" {
  description = "Version of Prometheus Helm chart"
  type        = string
  default     = "25.8.0"
}

variable "opencost_version" {
  description = "Version of OpenCost Helm chart"
  type        = string
  default     = "1.26.0"
}

# Allocation Export Variables
variable "enable_allocation_export" {
  description = "Enable CronJob to export OpenCost allocation data to Azure Storage"
  type        = bool
  default     = true
}

variable "allocation_export_schedule" {
  description = "Cron schedule for allocation export (default: daily at 2 AM UTC)"
  type        = string
  default     = "0 2 * * *"
}

variable "allocation_export_window" {
  description = "Time window for allocation export (e.g., 24h, 7d, yesterday)"
  type        = string
  default     = "24h"
}

variable "allocation_export_aggregate" {
  description = "Aggregation level for allocation export"
  type        = string
  default     = "namespace,controller,pod"
}

variable "allocation_export_container_name" {
  description = "Name of the storage container for allocation exports"
  type        = string
  default     = "allocation-exports"
}

# Sample Applications Variables
variable "deploy_sample_apps" {
  description = "Deploy sample applications with cost allocation labels for demo purposes"
  type        = bool
  default     = true
}
