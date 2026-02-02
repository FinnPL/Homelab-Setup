resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = "gateway"
  }
}

resource "kubectl_manifest" "wildcard_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-lippok-dev"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      secretName = "wildcard-lippok-dev-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      commonName = "*.lippok.dev"
      dnsNames = [
        "lippok.dev",
        "*.lippok.dev"
      ]
    }
  })

  depends_on = [kubectl_manifest.letsencrypt_prod]
}

resource "kubectl_manifest" "main_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "main-gateway"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
      annotations = {
        "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      }
    }
    spec = {
      gatewayClassName = "cilium"
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 443
          tls = {
            mode = "Terminate"
            certificateRefs = [
              {
                name = "wildcard-lippok-dev-tls"
              }
            ]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
    }
  })

  depends_on = [
    helm_release.cilium,
    kubectl_manifest.gateway_api_crds,
    kubectl_manifest.wildcard_certificate
  ]
}

# Data source to get the Gateway's LoadBalancer IP after creation
data "kubernetes_service_v1" "gateway_lb" {
  metadata {
    name      = "cilium-gateway-main-gateway"
    namespace = kubernetes_namespace_v1.gateway.metadata[0].name
  }

  depends_on = [kubectl_manifest.main_gateway]
}

locals {
  gateway_lb_ip = try(
    data.kubernetes_service_v1.gateway_lb.status[0].load_balancer[0].ingress[0].ip,
    null
  )
}
