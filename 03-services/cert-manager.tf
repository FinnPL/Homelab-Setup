resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name            = "cert-manager"
  repository      = "https://charts.jetstack.io"
  chart           = "cert-manager"
  version         = "1.17.2"
  namespace       = kubernetes_namespace_v1.cert_manager.metadata[0].name
  timeout         = 600
  cleanup_on_fail = true

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
      config = {
        apiVersion       = "controller.cert-manager.io/v1alpha1"
        kind             = "ControllerConfiguration"
        enableGatewayAPI = true
      }
    })
  ]

  depends_on = [helm_release.cilium]
}

resource "kubernetes_secret_v1" "cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  }

  data = {
    api-token = var.cloudflare_api_token
  }

  type = "Opaque"
}

resource "kubectl_manifest" "letsencrypt_prod" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cloudflare_api_token.metadata[0].name
                  key  = "api-token"
                }
              }
            }
            selector = {
              dnsZones = ["lippok.dev"]
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}
