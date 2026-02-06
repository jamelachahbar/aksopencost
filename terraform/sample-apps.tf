# Sample Applications with Cost Allocation Labels
# These deployments demonstrate cost allocation by cost-center, team, project, and environment

# ============================================================================
# API Service - Backend Team (Cost Center: CC-2001)
# ============================================================================
resource "kubernetes_deployment" "api_service" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "api-service"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    labels = {
      app         = "api-service"
      version     = "v1.0.0"
      team        = "backend"
      project     = "customer-api"
      environment = "production"
      cost-center = "CC-2001"
    }
  }

  spec {
    replicas = 3

    selector {
      match_labels = {
        app = "api-service"
      }
    }

    template {
      metadata {
        labels = {
          app         = "api-service"
          team        = "backend"
          project     = "customer-api"
          environment = "production"
          cost-center = "CC-2001"
        }
      }

      spec {
        container {
          name  = "api"
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.sample_app]
}

resource "kubernetes_service" "api_service" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "api-service"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
  }

  spec {
    selector = {
      app = "api-service"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "ClusterIP"
  }
}

# ============================================================================
# Web Frontend - Frontend Team (Cost Center: CC-2002)
# ============================================================================
resource "kubernetes_deployment" "web_frontend" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "web-frontend"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    labels = {
      app         = "web-frontend"
      version     = "v2.1.0"
      team        = "frontend"
      project     = "customer-portal"
      environment = "production"
      cost-center = "CC-2002"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "web-frontend"
      }
    }

    template {
      metadata {
        labels = {
          app         = "web-frontend"
          team        = "frontend"
          project     = "customer-portal"
          environment = "production"
          cost-center = "CC-2002"
        }
      }

      spec {
        container {
          name  = "web"
          image = "nginx:alpine"

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.sample_app]
}

resource "kubernetes_service" "web_frontend" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "web-frontend"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
  }

  spec {
    selector = {
      app = "web-frontend"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}

# ============================================================================
# Data Processor - Data Team (Cost Center: CC-3001)
# ============================================================================
resource "kubernetes_deployment" "data_processor" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "data-processor"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    labels = {
      app         = "data-processor"
      version     = "v1.5.0"
      team        = "data"
      project     = "analytics-pipeline"
      environment = "production"
      cost-center = "CC-3001"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "data-processor"
      }
    }

    template {
      metadata {
        labels = {
          app         = "data-processor"
          team        = "data"
          project     = "analytics-pipeline"
          environment = "production"
          cost-center = "CC-3001"
        }
      }

      spec {
        container {
          name  = "processor"
          image = "redis:alpine"

          port {
            container_port = 6379
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.sample_app]
}

# ============================================================================
# ML Training Job - ML Team (Cost Center: CC-4001)
# ============================================================================
resource "kubernetes_deployment" "ml_training" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "ml-training"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    labels = {
      app         = "ml-training"
      version     = "v0.9.0"
      team        = "ml-engineering"
      project     = "recommendation-engine"
      environment = "development"
      cost-center = "CC-4001"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ml-training"
      }
    }

    template {
      metadata {
        labels = {
          app         = "ml-training"
          team        = "ml-engineering"
          project     = "recommendation-engine"
          environment = "development"
          cost-center = "CC-4001"
        }
      }

      spec {
        container {
          name  = "trainer"
          image = "python:3.11-alpine"

          command = ["sleep", "infinity"]

          resources {
            requests = {
              cpu    = "500m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "2000m"
              memory = "1Gi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.sample_app]
}

# ============================================================================
# Shared Services - Platform Team (Cost Center: CC-1001)
# ============================================================================
resource "kubernetes_deployment" "shared_cache" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "shared-cache"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
    labels = {
      app         = "shared-cache"
      version     = "v1.0.0"
      team        = "platform"
      project     = "shared-infrastructure"
      environment = "production"
      cost-center = "CC-1001"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "shared-cache"
      }
    }

    template {
      metadata {
        labels = {
          app         = "shared-cache"
          team        = "platform"
          project     = "shared-infrastructure"
          environment = "production"
          cost-center = "CC-1001"
        }
      }

      spec {
        container {
          name  = "cache"
          image = "redis:alpine"

          port {
            container_port = 6379
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.sample_app]
}

resource "kubernetes_service" "shared_cache" {
  count = var.deploy_sample_apps ? 1 : 0

  metadata {
    name      = "shared-cache"
    namespace = kubernetes_namespace.sample_app.metadata[0].name
  }

  spec {
    selector = {
      app = "shared-cache"
    }

    port {
      port        = 6379
      target_port = 6379
    }

    type = "ClusterIP"
  }
}
