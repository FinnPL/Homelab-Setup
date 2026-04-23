resource "kubernetes_namespace_v1" "external_dns" {
  count = var.cloudflare_api_token != "" ? 1 : 0

  metadata {
    name = "external-dns"
  }
}

resource "kubectl_manifest" "external_dns_cloudflare_secret" {
  count = var.cloudflare_api_token != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = "cloudflare-api-token"
      namespace = kubernetes_namespace_v1.external_dns[0].metadata[0].name
    }
    type = "Opaque"
    stringData = {
      api-token = var.cloudflare_api_token
    }
  })
}

resource "helm_release" "external_dns" {
  count = var.cloudflare_api_token != "" ? 1 : 0

  name            = "external-dns"
  repository      = "https://kubernetes-sigs.github.io/external-dns/"
  chart           = "external-dns"
  version         = var.external_dns_version
  namespace       = kubernetes_namespace_v1.external_dns[0].metadata[0].name
  timeout         = 300
  replace         = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      provider = {
        name = "cloudflare"
      }
      env = [
        {
          name = "CF_API_TOKEN"
          valueFrom = {
            secretKeyRef = {
              name = "cloudflare-api-token"
              key  = "api-token"
            }
          }
        }
      ]
      sources = [
        "gateway-httproute",
        "gateway-tlsroute",
      ]
      domainFilters = ["lippok.dev"]
      policy        = "sync"
      txtOwnerId    = "cloud-edge"
      txtPrefix     = "extdns-"
    })
  ]

  depends_on = [
    helm_release.cilium,
    kubectl_manifest.gateway_api_crds,
    kubectl_manifest.external_dns_cloudflare_secret,
  ]
}
