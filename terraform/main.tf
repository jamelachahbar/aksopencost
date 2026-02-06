data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}

# Random suffix for globally unique names
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                = "default"
    node_count          = var.enable_auto_scaling ? null : var.node_count
    vm_size             = var.node_vm_size
    enable_auto_scaling = var.enable_auto_scaling
    min_count           = var.enable_auto_scaling ? var.min_node_count : null
    max_count           = var.enable_auto_scaling ? var.max_node_count : null
    os_disk_size_gb     = 30
    type                = "VirtualMachineScaleSets"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = var.network_plugin
    network_policy = var.network_policy
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }

  tags = var.tags
}

# Custom Role Definition for OpenCost
resource "azurerm_role_definition" "opencost_role" {
  name        = "OpenCostRole-${random_string.suffix.result}"
  scope       = data.azurerm_subscription.current.id
  description = "Rate Card query role for OpenCost"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/vmSizes/read",
      "Microsoft.Resources/subscriptions/locations/read",
      "Microsoft.Resources/providers/read",
      "Microsoft.ContainerService/containerServices/read",
      "Microsoft.Commerce/RateCard/read"
    ]
    not_actions = []
  }

  assignable_scopes = [
    data.azurerm_subscription.current.id
  ]
}

# Service Principal for OpenCost
resource "azuread_application" "opencost" {
  display_name = "OpenCostAccess-${random_string.suffix.result}"
}

resource "azuread_service_principal" "opencost" {
  client_id = azuread_application.opencost.client_id
}

resource "azuread_service_principal_password" "opencost" {
  service_principal_id = azuread_service_principal.opencost.id
}

# Role Assignment for Service Principal
resource "azurerm_role_assignment" "opencost_sp" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.opencost_role.role_definition_resource_id
  principal_id       = azuread_service_principal.opencost.object_id
}

# OpenCost Namespace
resource "kubernetes_namespace" "opencost" {
  metadata {
    name = "opencost"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Service Key Secret for OpenCost
resource "kubernetes_secret" "azure_service_key" {
  metadata {
    name      = "azure-service-key"
    namespace = kubernetes_namespace.opencost.metadata[0].name
  }

  data = {
    "service-key.json" = jsonencode({
      subscriptionId = data.azurerm_subscription.current.subscription_id
      serviceKey = {
        appId       = azuread_application.opencost.client_id
        displayName = azuread_application.opencost.display_name
        password    = azuread_service_principal_password.opencost.value
        tenant      = data.azurerm_client_config.current.tenant_id
      }
    })
  }

  type = "Opaque"
}

# Prometheus Namespace
resource "kubernetes_namespace" "prometheus" {
  metadata {
    name = "prometheus-system"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Prometheus Helm Release
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  version    = var.prometheus_version
  namespace  = kubernetes_namespace.prometheus.metadata[0].name

  set {
    name  = "prometheus-pushgateway.enabled"
    value = "false"
  }

  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  values = [
    file("${path.module}/files/prometheus-values.yaml")
  ]

  depends_on = [kubernetes_namespace.prometheus]
}

# OpenCost Helm Release
resource "helm_release" "opencost" {
  name       = "opencost"
  repository = "https://opencost.github.io/opencost-helm-chart"
  chart      = "opencost"
  version    = var.opencost_version
  namespace  = kubernetes_namespace.opencost.metadata[0].name

  set {
    name  = "opencost.exporter.defaultClusterId"
    value = var.cluster_name
  }

  set {
    name  = "opencost.prometheus.internal.enabled"
    value = "false"
  }

  set {
    name  = "opencost.prometheus.external.enabled"
    value = "true"
  }

  set {
    name  = "opencost.prometheus.external.url"
    value = "http://prometheus-server.prometheus-system.svc.cluster.local"
  }

  set {
    name  = "opencost.ui.enabled"
    value = "true"
  }

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  values = [
    yamlencode({
      opencost = {
        exporter = {
          extraVolumeMounts = [
            {
              mountPath = "/var/secrets"
              name      = "service-key-secret"
            }
          ]
        }
      }
      extraVolumes = [
        {
          name = "service-key-secret"
          secret = {
            secretName = kubernetes_secret.azure_service_key.metadata[0].name
          }
        }
      ]
    })
  ]

  depends_on = [
    helm_release.prometheus,
    kubernetes_secret.azure_service_key
  ]
}

# Sample Application Namespace
resource "kubernetes_namespace" "sample_app" {
  metadata {
    name = "sample-app"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}
