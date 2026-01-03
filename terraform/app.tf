# Namespace
resource "kubernetes_namespace" "esewans" {
  metadata {
    name = var.namespace_name
  }
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

resource "helm_release" "nginx_ingress" {
  name             = "nginx-ingress"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
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
      port        = 8080  # Service port
      target_port = 8080  # Container port
      node_port   = 30081 # Node port (external access via LoadBalancer)
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


resource "kubernetes_ingress_v1" "elasticsearch_ingress" {
  metadata {
    name      = "elasticsearch-ingress"
    namespace = kubernetes_namespace.elk_stack.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                       = "nginx"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "600"
      "nginx.ingress.kubernetes.io/proxy-body-size"       = "100m"
      "nginx.ingress.kubernetes.io/backend-protocol"      = "HTTPS"
      "nginx.ingress.kubernetes.io/proxy-ssl-verify"      = "false"
    }
  }

  spec {
    rule {
      host = "elasticsearch.sudarshan-uprety.com.np"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "elasticsearch-master"
              port {
                number = 9200
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.elasticsearch,
    helm_release.nginx_ingress
  ]

  timeouts {
    create = "5m"
    delete = "5m"
  }
}

resource "kubernetes_ingress_v1" "kibana_ingress" {
  metadata {
    name      = "kibana-ingress"
    namespace = kubernetes_namespace.elk_stack.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                       = "nginx"
      "nginx.ingress.kubernetes.io/proxy-connect-timeout" = "300"
      "nginx.ingress.kubernetes.io/proxy-send-timeout"    = "300"
      "nginx.ingress.kubernetes.io/proxy-read-timeout"    = "300"
    }
  }

  spec {
    rule {
      host = "kibana.sudarshan-uprety.com.np"
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "kibana-kibana"
              port {
                number = 5601
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.kibana,
    helm_release.nginx_ingress
  ]

  timeouts {
    create = "5m"
    delete = "5m"
  }
}
