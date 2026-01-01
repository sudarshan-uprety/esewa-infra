variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  default     = "esewa-resources"
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "southindia"
}

variable "cluster_name" {
  description = "The name of the AKS cluster"
  type        = string
  default     = "esewa-cluser"
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = "esewa-aks"
}

variable "namespace_name" {
  description = "The name of the Kubernetes namespace"
  type        = string
  default     = "esewans"
}
