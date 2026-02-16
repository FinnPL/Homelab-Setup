resource "kubernetes_namespace_v1" "vault" {
  metadata {
    name = "vault"
  }
}

resource "kubectl_manifest" "vault_service" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "vault-external"
      namespace = kubernetes_namespace_v1.vault.metadata[0].name
    }
    spec = {
      type = "ClusterIP"
      ports = [
        {
          name       = "http"
          protocol   = "TCP"
          port       = 8200
          targetPort = 8200
        }
      ]
    }
  })

  depends_on = [kubernetes_namespace_v1.vault]
}

resource "kubectl_manifest" "vault_endpoints" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Endpoints"
    metadata = {
      name      = "vault-external"
      namespace = kubernetes_namespace_v1.vault.metadata[0].name
    }
    subsets = [
      {
        addresses = [
          {
            ip = data.terraform_remote_state.infrastructure.outputs.vault_server.ip
          }
        ]
        ports = [
          {
            name     = "http"
            port     = 8200
            protocol = "TCP"
          }
        ]
      }
    ]
  })

  depends_on = [kubectl_manifest.vault_service]
}
