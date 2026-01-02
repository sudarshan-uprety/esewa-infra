terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "esewa" {
  name     = var.resource_group_name
  location = var.location
}

resource "kubernetes_secret" "docker_registry" {
  metadata {
    name      = "docker-hub-secret"
    namespace = kubernetes_namespace.esewans.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"
  
  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "https://index.docker.io/v1/" = {
          username = var.dockerhub_username
          password = var.dockerhub_password
        }
      }
    })
  }
}

# AKS Cluster
resource "azurerm_kubernetes_cluster" "esewa" {
  name                = var.cluster_name
  location            = azurerm_resource_group.esewa.location
  resource_group_name = azurerm_resource_group.esewa.name
  dns_prefix          = var.dns_prefix

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2s_v3"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Production"
  }
}


# Additional worker node pool
resource "azurerm_kubernetes_cluster_node_pool" "workernode" {
  name                  = "workernode"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.esewa.id
  vm_size               = "Standard_B2s_v2"
  enable_auto_scaling   = true
  min_count             = 1
  max_count             = 2

  tags = {
    Environment = "Production"
  }
}

# Kubernetes Provider
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.esewa.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.cluster_ca_certificate)
}

# helm provider
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.esewa.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.cluster_ca_certificate)
  }
}

# Namespace
resource "kubernetes_namespace" "esewans" {
  metadata {
    name = var.namespace_name
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"
  create_namespace = true
  
  # Configure as LoadBalancer for external access
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  
  # Health check for Azure Load Balancer
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }
  
  # Run 2 replicas for high availability
  set {
    name  = "controller.replicaCount"
    value = "2"
  }
  
  # Wait for installation to complete
  wait = true
  
  # Dependencies: Install AFTER AKS cluster is ready
  depends_on = [
    azurerm_kubernetes_cluster.esewa,
    azurerm_kubernetes_cluster_node_pool.workernode
  ]
}

# Kubernetes Deployment (Java App)
resource "kubernetes_deployment" "esewa_app" {
  metadata {
    name      = "esewa-app"
    namespace = kubernetes_namespace.esewans.metadata[0].name
    labels    = { app = "esewa-app" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "esewa-app" }
    }
    template {
      metadata {
        labels = { app = "esewa-app" }
      }
      spec {
        image_pull_secrets {
          name = kubernetes_secret.docker_registry.metadata[0].name
        }
        container {
          name  = "esewa-app"
          image = var.docker_image
          port {
            container_port = 8080
          }
          # Add liveness and readiness probes
          liveness_probe {
            http_get {
              path = "/api/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          readiness_probe {
            http_get {
              path = "/api/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }
      }
    }
  }
  timeouts {
    create = "15m"
    update = "15m"
    delete = "10m"
  }
}

# LoadBalancer servicee
resource "kubernetes_service" "esewa_svc" {
  metadata {
    name      = "esewa-service"
    namespace = kubernetes_namespace.esewans.metadata[0].name
  }
  spec {
    selector = { app = "esewa-app" }
    port {
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_service" "esewa_nodeport" {
  metadata {
    name      = "esewa-nodeport"
    namespace = kubernetes_namespace.esewans.metadata[0].name
  }
  spec {
    selector = { app = "esewa-app" }
    port {
      name        = "http"
      port        = 8080        # Service port
      target_port = 8080        # Container port
      node_port   = 30081      # Node port (external access via LoadBalancer)
      protocol    = "TCP"
    }
    type = "NodePort"
  }
}

resource "kubernetes_ingress_v1" "esewa_ingress" {
  metadata {
    name      = "esewa-ingress"
    namespace = kubernetes_namespace.esewans.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                = "nginx"
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }
  
  spec {
    rule {
      host = "esewa.sudarshan-uprety.com.np"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.esewa_nodeport.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
  timeouts {
    create = "5m"
    delete = "5m"
  }
}


resource "kubernetes_namespace" "elk_stack" {
  metadata {
    name = "elk-stack"
    labels = {
      name        = "elk-stack"
      environment = "production"
    }
  }
}

resource "helm_release" "elasticsearch" {
  name       = "elasticsearch"
  repository = "https://helm.elastic.co"
  chart      = "elasticsearch"
  namespace  = kubernetes_namespace.elk_stack.metadata[0].name
  version    = "8.5.1"  # Use latest stable

  # Use your YAML file
  values = [
    file("${path.module}/helm-values/elasticsearch-values.yaml")
  ]

  depends_on = [
    kubernetes_namespace.elk_stack,
    azurerm_kubernetes_cluster_node_pool.workernode
  ]

  wait    = true
  timeout = 900  # 15 minutes
}

# Deploy Kibana using external YAML
resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = kubernetes_namespace.elk_stack.metadata[0].name
  version    = "8.5.1"
  
  # Use external YAML file
  values = [
    file("${path.module}/helm-values/kibana-values.yaml")
  ]
  
  depends_on = [helm_release.elasticsearch]
  
  wait    = true
  timeout = 300
}

# Deploy Filebeat using external YAML
resource "helm_release" "filebeat" {
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  namespace  = kubernetes_namespace.elk_stack.metadata[0].name
  version    = "8.5.1"
  
  # Use external YAML file + dynamic values
  values = [
    file("${path.module}/helm-values/filebeat-values.yaml")
  ]
  
  depends_on = [helm_release.elasticsearch]
}
