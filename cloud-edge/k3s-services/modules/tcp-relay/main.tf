# Reusable L4 TCP relay.
#
# Deploys a minimal nginx `stream` passthrough pod behind a ClusterIP Service.
# Forwards bytes at L4 — TLS/SNI/ALPN are untouched. Useful for giving Gateway
# TLSRoutes a pod-CIDR source IP before a cluster-mesh hop, or for any case
# where you need a stable in-cluster Service to front an external TCP target.
#
# Intentional design choices:
# - Upstream is resolved at connection time via nginx's `resolver` directive
#   with a variable in proxy_pass. Avoids baking the ClusterIP into the
#   ConfigMap, which breaks on Service recreation.
# - Runs as non-root on a privileged-port-free listener (listen_port >= 1024),
#   the Service then maps service_port -> listen_port.
# - Pod Security: runAsNonRoot, seccompProfile RuntimeDefault, drop ALL caps,
#   no privilege escalation.

locals {
  app_label = var.name

  nginx_conf = <<-EOT
    worker_processes auto;
    pid /tmp/nginx.pid;
    error_log /dev/stderr warn;

    events {
      worker_connections 1024;
    }

    stream {
      access_log off;
      resolver ${var.resolver} valid=${var.resolver_valid} ipv6=off;

      server {
        listen ${var.listen_port};
        set $upstream "${var.upstream_host}:${var.upstream_port}";
        proxy_pass $upstream;
        proxy_connect_timeout ${var.proxy_connect_timeout};
        proxy_timeout ${var.proxy_timeout};
      }
    }
  EOT
}

resource "kubernetes_config_map_v1" "nginx" {
  metadata {
    name      = "${var.name}-nginx"
    namespace = var.namespace
  }

  data = {
    "nginx.conf" = local.nginx_conf
  }
}

resource "kubernetes_deployment_v1" "relay" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels = {
      app = local.app_label
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = local.app_label
      }
    }

    template {
      metadata {
        labels = {
          app = local.app_label
        }
        annotations = {
          # Forces a rolling restart on nginx.conf changes.
          "checksum/nginx-conf" = sha256(local.nginx_conf)
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
          image = var.image

          port {
            name           = "tcp"
            container_port = var.listen_port
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
              port = var.listen_port
            }
            initial_delay_seconds = 2
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = var.resources.requests.cpu
              memory = var.resources.requests.memory
            }
            limits = {
              cpu    = var.resources.limits.cpu
              memory = var.resources.limits.memory
            }
          }
        }

        volume {
          name = "nginx-conf"
          config_map {
            name = kubernetes_config_map_v1.nginx.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "relay" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    selector = {
      app = local.app_label
    }
    port {
      name        = "tcp"
      port        = var.service_port
      target_port = var.listen_port
      protocol    = "TCP"
    }
  }
}
