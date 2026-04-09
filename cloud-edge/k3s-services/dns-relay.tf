# DNS relay: forwards DoH traffic from the public cloud edge to Blocky in the homelab.
# True E2EE: the cloud Gateway is in TLS Passthrough mode for *.relay.lippok.dev.

resource "kubernetes_namespace_v1" "dns" {
  metadata {
    name = "dns"
  }
}

resource "kubectl_manifest" "dns_reference_grant" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-gateway-to-dns"
      namespace = kubernetes_namespace_v1.dns.metadata[0].name
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "TLSRoute"
          namespace = kubernetes_namespace_v1.gateway.metadata[0].name
        }
      ]
      to = [
        {
          group = "multicluster.x-k8s.io"
          kind  = "ServiceImport"
        },
        {
          group = ""
          kind  = "Service"
        },
      ]
    }
  })

  depends_on = [
    kubectl_manifest.gateway_api_crds,
    kubernetes_namespace_v1.dns,
  ]
}

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
              # MCS-API: route to the ServiceImport that Cilium materialises from the homelab's ServiceExport.
              group     = "multicluster.x-k8s.io"
              kind      = "ServiceImport"
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
    kubectl_manifest.cloud_gateway,
    kubectl_manifest.dns_reference_grant,
  ]
}
