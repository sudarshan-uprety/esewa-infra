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
  version    = "8.5.1" # Use latest stable

  values = [
    file("${path.module}/helm-values/elasticsearch-values.yaml")
  ]

  wait_for_jobs = true

  # ✅ CREATE KUBERNETES RESOURCE TO WAIT FOR ELASTICSEARCH
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Elasticsearch to be ready..."
      kubectl wait --namespace ${self.namespace} \
        --for=condition=ready pod \
        --selector=app=elasticsearch-master \
        --timeout=300s
    EOT
  }

  depends_on = [
    kubernetes_namespace.elk_stack,
    azurerm_kubernetes_cluster_node_pool.workernode
  ]
}


resource "null_resource" "setup_kibana_user" {
  depends_on = [
    helm_release.elasticsearch,
    null_resource.elasticsearch_ready
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for Elasticsearch to be fully ready
      sleep 30
      
      # Get elastic password
      ELASTIC_PASSWORD=$(kubectl get secret elasticsearch-master-credentials -n elk-stack -o jsonpath='{.data.password}' | base64 -d)
      
      # Set kibana_system user password
      kubectl exec -n elk-stack elasticsearch-master-0 -- \
        curl -X POST 'https://localhost:9200/_security/user/kibana_system/_password' \
        -k -u "elastic:$ELASTIC_PASSWORD" \
        -H 'Content-Type: application/json' \
        -d '{"password": "KibanaPassword123!"}'
      
      echo "Kibana system user password set successfully"
    EOT
  }

  triggers = {
    elasticsearch_id = helm_release.elasticsearch.id
  }
}

resource "kubernetes_secret" "kibana_credentials" {
  metadata {
    name      = "kibana-elasticsearch-credentials"
    namespace = kubernetes_namespace.elk_stack.metadata[0].name
  }

  data = {
    username = "kibana_system"
    password = "KibanaPassword123!"
  }

  type = "Opaque"

  depends_on = [null_resource.setup_kibana_user]
}


resource "kubernetes_secret" "kibana_dummy_token" {
  metadata {
    name      = "kibana-kibana-es-token"
    namespace = kubernetes_namespace.elk_stack.metadata[0].name
  }

  data = {
    token = ""
  }

  type = "Opaque"

  depends_on = [kubernetes_namespace.elk_stack]
}

# Deploy Kibana using external YAML
resource "helm_release" "kibana" {
  name       = "kibana"
  repository = "https://helm.elastic.co"
  chart      = "kibana"
  namespace  = kubernetes_namespace.elk_stack.metadata[0].name
  version    = "8.5.1"

  values = [
    yamlencode({
      replicas = 1

      service = {
        type     = "NodePort"
        nodePort = 30561
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "512Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      elasticsearchHosts = "https://elasticsearch-master:9200"

      protocol = "http"

      serviceAccountToken = {
        enabled = false
      }

      createCert = false

      extraEnvs = [
        {
          name = "ELASTICSEARCH_USERNAME"
          valueFrom = {
            secretKeyRef = {
              name = "kibana-elasticsearch-credentials"
              key  = "username"
            }
          }
        },
        {
          name = "ELASTICSEARCH_PASSWORD"
          valueFrom = {
            secretKeyRef = {
              name = "kibana-elasticsearch-credentials"
              key  = "password"
            }
          }
        },
        {
          name  = "ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES"
          value = "/usr/share/kibana/config/certs/ca.crt"
        }
      ]

      # Override the default probes completely
      healthCheckPath = "/api/status"

      readinessProbe = {
        exec = {
          command = [
            "sh",
            "-c",
            "curl -f http://localhost:5601/api/status || exit 1"
          ]
        }
        initialDelaySeconds = 60
        periodSeconds       = 10
        timeoutSeconds      = 5
        failureThreshold    = 10
      }

      livenessProbe = {
        exec = {
          command = [
            "sh",
            "-c",
            "curl -f http://localhost:5601/api/status || exit 1"
          ]
        }
        initialDelaySeconds = 120
        periodSeconds       = 10
        timeoutSeconds      = 5
        failureThreshold    = 10
      }
    })
  ]

  disable_webhooks = true

  replace         = true
  force_update    = true
  cleanup_on_fail = true
  recreate_pods   = true

  wait          = true
  timeout       = 900
  wait_for_jobs = false

  depends_on = [
    helm_release.elasticsearch,
    null_resource.elasticsearch_ready,
    kubernetes_secret.kibana_credentials,
    kubernetes_secret.kibana_dummy_token
  ]
}


# Deploy Filebeat using external YAML
resource "helm_release" "filebeat" {
  name       = "filebeat"
  repository = "https://helm.elastic.co"
  chart      = "filebeat"
  namespace  = kubernetes_namespace.elk_stack.metadata[0].name
  version    = "8.5.1"

  values = [
    file("${path.module}/helm-values/filebeat-values.yaml")
  ]

  set {
    name  = "extraEnvs[0].name"
    value = "ELASTICSEARCH_USERNAME"
  }

  set {
    name  = "extraEnvs[0].value"
    value = "elastic"
  }

  set {
    name  = "extraEnvs[1].name"
    value = "ELASTICSEARCH_PASSWORD"
  }

  set {
    name  = "extraEnvs[1].valueFrom.secretKeyRef.name"
    value = "elasticsearch-master-credentials"
  }

  set {
    name  = "extraEnvs[1].valueFrom.secretKeyRef.key"
    value = "password"
  }

  depends_on = [helm_release.elasticsearch]

  wait = false # Install async
}

# CREATE NULL RESOURCE TO TRACK ELASTICSEARCH READINESS
resource "null_resource" "elasticsearch_ready" {
  depends_on = [helm_release.elasticsearch]

  triggers = {
    elasticsearch_id = helm_release.elasticsearch.id
  }
}
