# DNS relay: forwards DoH traffic from the public cloud edge to Blocky in the homelab.
# True E2EE: the cloud Gateway is in TLS Passthrough mode for *.relay.lippok.dev.
#
# Why the relay pod exists:
# Cilium Gateway (hostNetwork Envoy DaemonSet, default in v1.19.x) sources
# upstream connections from the reserved:ingress identity IP (10.42.0.185). That
# IP has no kernel socket binding on the node, so SYN/ACK return traffic across
# the Cluster Mesh tunnel arrives on cilium_host but never reaches Envoy's
# socket — the handshake times out. Routing through a normal pod-CIDR relay
# restores the return path (pod->pod across the mesh works fine).
#
# TLS passthrough is preserved: the relay uses nginx `stream` at L4, so SNI /
# ALPN / certificates are untouched.

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

# Look up the Cilium-derived Service backing the MCS-API ServiceImport `dns/dns`.
# Cilium names it `derived-<hash>`; we match by the standard MCS-API label.
# We pull the *name*, not the ClusterIP: the name is a deterministic hash of
# the ServiceImport UID, while the ClusterIP churns on any Service re-creation.
# nginx resolves the name dynamically via the kube-dns resolver, so ClusterIP
# changes are picked up within `resolver_valid` without a TF apply.
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
  # Fresh-bootstrap guard: Cilium hasn't reconciled the ServiceImport yet on
  # the very first apply of a new cluster. count=0 keeps the relay + TLSRoute
  # absent until a second apply picks up the derived Service. Both the relay
  # resources and the TLSRoute share this gate so the route is never published
  # pointing at a Service that doesn't exist.
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
