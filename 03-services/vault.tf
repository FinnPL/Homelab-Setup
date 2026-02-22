resource "kubernetes_namespace_v1" "vault" {
  metadata {
    name = "vault"
  }
}

resource "kubernetes_service_v1" "vault_external" {
  metadata {
    name      = "vault-external"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
  }
  spec {
    type = "ClusterIP"
    port {
      name        = "https"
      protocol    = "TCP"
      port        = 8200
      target_port = 8200
      app_protocol = "https"
    }
  }
}

resource "kubernetes_endpoints_v1" "vault_external" {
  metadata {
    name      = kubernetes_service_v1.vault_external.metadata[0].name
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
  }
  subset {
    address {
      ip = data.terraform_remote_state.infrastructure.outputs.vault_server.ip
    }
    port {
      name     = "https"
      port     = 8200
      protocol = "TCP"
    }
  }
}

resource "kubernetes_config_map_v1" "vault_backend_ca" {
  metadata {
    name      = "vault-backend-ca"
    namespace = kubernetes_namespace_v1.vault.metadata[0].name
  }
  data = {
    "ca.crt" = data.terraform_remote_state.infrastructure.outputs.vault_server.ca_cert
  }
}

resource "kubectl_manifest" "vault_backend_tls_policy" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "BackendTLSPolicy"
    metadata = {
      name      = "vault-external-tls"
      namespace = kubernetes_namespace_v1.vault.metadata[0].name
    }
    spec = {
      targetRefs = [
        {
          group       = ""
          kind        = "Service"
          name        = kubernetes_service_v1.vault_external.metadata[0].name
          sectionName = "https"
        }
      ]
      validation = {
        hostname = "vault.lippok.dev"
        caCertificateRefs = [
          {
            group = ""
            kind  = "ConfigMap"
            name  = kubernetes_config_map_v1.vault_backend_ca.metadata[0].name
          }
        ]
      }
    }
  })

  depends_on = [
    kubectl_manifest.gateway_api_crds
  ]
}

resource "kubectl_manifest" "vault_httproute" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "vault"
      namespace = kubernetes_namespace_v1.vault.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name      = "main-gateway"
          namespace = "gateway"
        }
      ]
      hostnames = ["vault.lippok.dev"]
      rules = [
        {
          backendRefs = [
            {
              name = kubernetes_service_v1.vault_external.metadata[0].name
              port = 8200
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.gateway_api_crds
  ]
}
