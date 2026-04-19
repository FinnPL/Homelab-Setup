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

resource "tls_private_key" "internal_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "internal_ca" {
  private_key_pem = tls_private_key.internal_ca.private_key_pem

  subject {
    common_name = "homelab-internal-ca"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10y
  early_renewal_hours   = 2160  # renew when <90d remains

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

resource "kubernetes_secret_v1" "internal_ca" {
  metadata {
    name      = "internal-ca"
    namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_self_signed_cert.internal_ca.cert_pem
    "tls.key" = tls_private_key.internal_ca.private_key_pem
    "ca.crt"  = tls_self_signed_cert.internal_ca.cert_pem
  }
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

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret_v1.internal_ca,
  ]
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
