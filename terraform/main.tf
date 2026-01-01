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

# AKS Cluster
resource "azurerm_kubernetes_cluster" "esewa" {
  name                = var.cluster_name
  location            = azurerm_resource_group.esewa.location
  resource_group_name = azurerm_resource_group.esewa.name
  dns_prefix          = var.dns_prefix

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_DS2_v2"
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
  vm_size               = "Standard_DS2_v2"
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

# Namespace
resource "kubernetes_namespace" "esewans" {
  metadata {
    name = var.namespace_name
  }
}

# Kubernetes Deployment (Java App)
resource "kubernetes_deployment" "esewa_app" {
  metadata {
    name      = "esewa-app"
    namespace = kubernetes_namespace.esewans.metadata[0].name
    labels = { app = "esewa-app" }
  }

  spec {
    replicas = 2
    selector {
      match_labels = { app = "esewa-app" }
    }
    template {
      metadata {
        labels = { app = "esewa-app" }
      }
      spec {
        container {
          name  = "esewa-app"
          image = var.docker_image
          ports { container_port = 8080 }
        }
      }
    }
  }
}

# NodePort Service
resource "kubernetes_service" "esewa_svc" {
  metadata {
    name      = "esewa-service"
    namespace = kubernetes_namespace.esewans.metadata[0].name
  }
  spec {
    selector = { app = "esewa-app" }
    port {
      port        = 8080
      target_port = 8080
      node_port   = 30080
    }
    type = "NodePort"
  }
}

# (Optional) Ingress
resource "kubernetes_ingress" "esewa_ingress" {
  metadata {
    name      = "esewa-ingress"
    namespace = kubernetes_namespace.esewans.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      http {
        path {
          path = "/"
          backend {
            service_name = kubernetes_service.esewa_svc.metadata[0].name
            service_port = 8080
          }
        }
      }
    }
  }
}
