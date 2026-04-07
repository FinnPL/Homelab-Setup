# Relay routes: TLS passthrough routes that forward traffic to the homelab via Cluster Mesh.
# Each route attaches to the "relay-passthrough" listener on the cloud Gateway.

# DNS relay: forwards DoH traffic to homelab Blocky
resource "kubectl_manifest" "relay_dns" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1alpha2"
    kind       = "TLSRoute"
    metadata = {
      name      = "relay-dns"
      namespace = kubernetes_namespace_v1.gateway.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name        = "cloud-gateway"
          namespace   = kubernetes_namespace_v1.gateway.metadata[0].name
          sectionName = "relay-passthrough"
        }
      ]
      rules = [
        {
          backendRefs = [
            {
              name      = "dns"
              namespace = "dns"
              port      = 443
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    kubectl_manifest.cloud_gateway
  ]
}
