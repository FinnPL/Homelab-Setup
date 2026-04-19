resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name            = "cert-manager"
  repository      = "https://charts.jetstack.io"
  chart           = "cert-manager"
  version         = "v1.20.1"
  namespace       = kubernetes_namespace_v1.cert_manager.metadata[0].name
  timeout         = 600
  cleanup_on_fail = true

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
      config = {
        apiVersion       = "controller.config.cert-manager.io/v1alpha1"
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

resource "kubectl_manifest" "selfsigned_bootstrap_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "selfsigned-bootstrap"
    }
    spec = {
      selfSigned = {}
    }
  })

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "internal_ca_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "internal-ca"
      namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
    }
    spec = {
      isCA        = true
      commonName  = "homelab-internal-ca"
      secretName  = "internal-ca"
      duration    = "87600h" # 10y
      renewBefore = "2160h"  # 90d
      privateKey = {
        algorithm = "ECDSA"
        size      = 256
      }
      issuerRef = {
        name  = "selfsigned-bootstrap"
        kind  = "ClusterIssuer"
        group = "cert-manager.io"
      }
    }
  })

  depends_on = [kubectl_manifest.selfsigned_bootstrap_issuer]
}

resource "kubectl_manifest" "internal_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "internal-ca-issuer"
    }
    spec = {
      ca = {
        secretName = "internal-ca"
      }
    }
  })

  depends_on = [kubectl_manifest.internal_ca_certificate]
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
