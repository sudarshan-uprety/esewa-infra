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

resource "azurerm_resource_group" "esewa" {
  name     = var.resource_group_name
  location = var.location
}

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

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.esewa.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.esewa.kube_config.0.cluster_ca_certificate)
}

resource "kubernetes_namespace" "esewans" {
  metadata {
    name = var.namespace_name
  }
}
