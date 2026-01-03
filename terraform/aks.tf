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
