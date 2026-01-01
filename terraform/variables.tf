variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  default     = "esewa-resources"
}

variable "location" {
  description = "Azure region to deploy"
  type        = string
  default     = "southindia"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "esewa-cluster"
}

variable "dns_prefix" {
  description = "DNS prefix for AKS"
  type        = string
  default     = "esewa-aks"
}

variable "namespace_name" {
  description = "Kubernetes namespace"
  type        = string
  default     = "esewans"
}

variable "docker_image" {
  description = "Docker image for the application"
  type        = string
}
