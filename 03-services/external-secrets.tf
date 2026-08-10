resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.9.0"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      installCRDs = true
      resources = {
        requests = { cpu = "10m", memory = "64Mi" }
        limits   = { memory = "128Mi" }
      }
      certController = {
        resources = {
          requests = { cpu = "10m", memory = "64Mi" }
          limits   = { memory = "128Mi" }
        }
      }
      webhook = {
        resources = {
          requests = { cpu = "10m", memory = "32Mi" }
          limits   = { memory = "64Mi" }
        }
      }
    })
  ]

  depends_on = [helm_release.cilium]
}

# Authenticates with a projected service-account token against the vieta-cluster JWT
# mount, whose signing key is pinned in vault/vieta-sa-pubkey.pem.
resource "kubectl_manifest" "vault_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "vault-secret-store"
    }
    spec = {
      provider = {
        vault = {
          server  = var.vault_address
          path    = "kv"
          version = "v2"
          auth = {
            jwt = {
              path = "vieta-cluster"
              role = "eso"
              kubernetesServiceAccountToken = {
                serviceAccountRef = {
                  name      = "external-secrets"
                  namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
                }
                audiences         = ["vault"]
                expirationSeconds = 600
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}
