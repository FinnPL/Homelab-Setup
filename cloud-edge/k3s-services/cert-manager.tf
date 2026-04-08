# cert-manager for the cloud K3s cluster
# Used for TLS certificates on cloud-hosted services (*.cloud.lippok.dev)

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version
  namespace        = "cert-manager"
  create_namespace = true
  timeout          = 300
  replace          = true
  cleanup_on_fail  = true

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "cloud_issuer_secret" {
  count = var.cloudflare_api_token != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "cloudflare-api-token"
      namespace = "cert-manager"
    }
    type = "Opaque"
    stringData = {
      api-token = var.cloudflare_api_token
    }
  })

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "letsencrypt_prod" {
  count = var.acme_email != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = "cloudflare-api-token"
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.cert_manager,
    kubectl_manifest.cloud_issuer_secret
  ]
}
