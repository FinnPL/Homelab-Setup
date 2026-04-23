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

data "kubernetes_resources" "dns_derived" {
  api_version    = "v1"
  kind           = "Service"
  namespace      = kubernetes_namespace_v1.dns.metadata[0].name
  label_selector = "multicluster.kubernetes.io/service-name=dns"
}

locals {
  dns_derived_name = try(
    data.kubernetes_resources.dns_derived.objects[0].metadata.name,
    "",
  )
  # Fresh-bootstrap guard
  dns_relay_enabled = local.dns_derived_name != ""
  dns_upstream_host = local.dns_relay_enabled ? "${local.dns_derived_name}.${kubernetes_namespace_v1.dns.metadata[0].name}.svc.cluster.local" : ""
}

module "dns_relay" {
  source = "./modules/tcp-relay"
  count  = local.dns_relay_enabled ? 1 : 0

  name          = "dns-relay"
  namespace     = kubernetes_namespace_v1.dns.metadata[0].name
  listen_port   = 8443
  service_port  = 443
  upstream_host = local.dns_upstream_host
  upstream_port = 443
}

resource "kubectl_manifest" "relay_dns" {
  count = local.dns_relay_enabled ? 1 : 0

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
              group     = ""
              kind      = "Service"
              name      = module.dns_relay[0].service_name
              namespace = module.dns_relay[0].service_namespace
              port      = module.dns_relay[0].service_port
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
