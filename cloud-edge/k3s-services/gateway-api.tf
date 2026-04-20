data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/experimental-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each          = data.kubectl_file_documents.gateway_api_crds.manifests
  yaml_body         = each.value
  server_side_apply = true
  wait              = true
}

# Cloud gateway for services hosted on or relayed through the edge node
resource "kubernetes_namespace_v1" "gateway" {
  metadata {
    name = "gateway"
  }
}

# *.cloud.lippok.dev: HTTPS termination for cloud-hosted services
# *.relay.lippok.dev: TLS passthrough to homelab via Cluster Mesh
resource "kubectl_manifest" "cloud_gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "cloud-gateway"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      gatewayClassName = "cilium"
      infrastructure = {
        annotations = {
          "oci.oraclecloud.com/load-balancer-type" = "nlb"
          "oci.oraclecloud.com/reserved-ips"       = local.cloud_edge.gateway_lb_reserved_ip
        }
      }
      listeners = [
          # HTTP listener for ACME challenges and redirects
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
          # TLS passthrough for relay services
          {
            name     = "relay-passthrough"
            protocol = "TLS"
            port     = 443
            hostname = "*.relay.lippok.dev"
            tls = {
              mode = "Passthrough"
            }
            allowedRoutes = {
              namespaces = {
                from = "All"
              }
            }
          },
          # HTTPS termination for cloud-hosted services
          {
            name     = "cloud-https"
            protocol = "HTTPS"
            port     = 443
            hostname = "*.cloud.lippok.dev"
            tls = {
              mode = "Terminate"
              certificateRefs = [
                {
                  name = "wildcard-cloud-lippok-dev-tls"
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
    kubectl_manifest.gateway_api_crds
  ]
}

# Wildcard certificate for cloud-hosted services
resource "kubectl_manifest" "cloud_wildcard_certificate" {
  count = var.acme_email != "" ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "wildcard-cloud-lippok-dev"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      secretName = "wildcard-cloud-lippok-dev-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      commonName = "*.cloud.lippok.dev"
      dnsNames = [
        "cloud.lippok.dev",
        "*.cloud.lippok.dev"
      ]
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_prod,
    helm_release.cert_manager
  ]
}
