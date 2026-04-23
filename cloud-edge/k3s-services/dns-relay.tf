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

# L4 TCP relay pod: Cilium Gateway (hostNetwork Envoy) uses the reserved:ingress
# source identity (10.42.0.185). That IP has no kernel socket binding on the node,
# so SYN/ACK return traffic across the Cluster Mesh tunnel is dropped and the TLS
# handshake never completes. Forwarding through a regular pod first gives Envoy a
# real pod-CIDR destination; the cluster-mesh hop is then pod→pod and works
# normally. Pattern mirrors charts/gateway-external-routes/_backend-proxy.tpl but
# uses the nginx `stream` module for L4 passthrough (preserves SNI/TLS bytes).
data "kubernetes_resources" "dns_derived" {
  api_version    = "v1"
  kind           = "Service"
  namespace      = kubernetes_namespace_v1.dns.metadata[0].name
  label_selector = "multicluster.kubernetes.io/service-name=dns"
}

locals {
  dns_derived_cluster_ip = try(
    data.kubernetes_resources.dns_derived.objects[0].spec.clusterIP,
    "",
  )
  dns_relay_enabled = local.dns_derived_cluster_ip != ""
}

resource "kubernetes_config_map_v1" "dns_relay_nginx" {
  count = local.dns_relay_enabled ? 1 : 0

  metadata {
    name      = "dns-relay-nginx"
    namespace = kubernetes_namespace_v1.dns.metadata[0].name
  }

  data = {
    "nginx.conf" = <<-EOT
      worker_processes auto;
      pid /tmp/nginx.pid;
      error_log /dev/stderr warn;

      events {
        worker_connections 1024;
      }

      stream {
        access_log off;

        server {
          listen 8443;
          proxy_pass ${local.dns_derived_cluster_ip}:443;
          proxy_connect_timeout 5s;
          proxy_timeout 30s;
        }
      }
    EOT
  }
}

resource "kubernetes_deployment_v1" "dns_relay" {
  count = local.dns_relay_enabled ? 1 : 0

  metadata {
    name      = "dns-relay"
    namespace = kubernetes_namespace_v1.dns.metadata[0].name
    labels = {
      app = "dns-relay"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "dns-relay"
      }
    }

    template {
      metadata {
        labels = {
          app = "dns-relay"
        }
        annotations = {
          "checksum/nginx-conf" = sha256(kubernetes_config_map_v1.dns_relay_nginx[0].data["nginx.conf"])
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "nginx"
          image = "nginxinc/nginx-unprivileged:1.29-alpine"

          port {
            name           = "doh-tls"
            container_port = 8443
            protocol       = "TCP"
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "nginx-conf"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
            read_only  = true
          }

          readiness_probe {
            tcp_socket {
              port = 8443
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "nginx-conf"
          config_map {
            name = kubernetes_config_map_v1.dns_relay_nginx[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "dns_relay" {
  count = local.dns_relay_enabled ? 1 : 0

  metadata {
    name      = "dns-relay"
    namespace = kubernetes_namespace_v1.dns.metadata[0].name
  }

  spec {
    selector = {
      app = "dns-relay"
    }
    port {
      name        = "doh-tls"
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }
  }
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
              # Route to the in-cluster nginx L4 relay Service (see comment above
              # on kubernetes_deployment_v1.dns_relay). The relay forwards to the
              # Cilium-derived Service for the MCS-API ServiceImport dns/dns.
              group     = ""
              kind      = "Service"
              name      = "dns-relay"
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
