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
