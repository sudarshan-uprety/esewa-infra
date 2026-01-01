output "cluster_name" {
  value = azurerm_kubernetes_cluster.esewa.name
}

output "resource_group_name" {
  value = azurerm_resource_group.esewa.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.esewa.kube_config_raw
  sensitive = true
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.esewa.kube_config.0.client_certificate
  sensitive = true
}
