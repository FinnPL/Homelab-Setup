resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.19.2"
  namespace  = "kube-system"
  timeout    = 600

  values = [
    yamlencode({
      kubeProxyReplacement = "true"
      k8sServiceHost       = "127.0.0.1"
      k8sServicePort       = 7445
      ipam = {
        mode = "kubernetes"
      }

      # Cluster identity for Cluster Mesh (cloud-edge is id=2)
      cluster = {
        name = "homelab-k8s"
        id   = 1
      }

      # Cluster Mesh: enable apiserver for cross-cluster connectivity
      clustermesh = {
        useAPIServer = true
        apiserver = {
          service = {
            type = "LoadBalancer"
          }
        }
      }
      l2announcements = {
        enabled = true
      }
      gatewayAPI = {
        enabled = true
      }
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
      securityContext = {
        capabilities = {
          ciliumAgent = [
            "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK",
            "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"
          ]
          cleanCiliumState = [
            "NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"
          ]
        }
      }

      hubble = {
        enabled = true
        relay = {
          enabled = true
          prometheus = {
            enabled = true
            serviceMonitor = {
              enabled  = true
              interval = "30s"
              labels = {
                release = "kube-prometheus-stack"
              }
            }
          }
        }
        ui = {
          enabled = true
        }
        metrics = {
          enableOpenMetrics = true
          enabled = [
            "dns:query;ignoreAAAA",
            "drop",
            "tcp",
            "icmp"
          ]
          serviceMonitor = {
            enabled  = true
            interval = "30s"
            labels = {
              release = "kube-prometheus-stack"
            }
          }
        }
      }

      prometheus = {
        enabled = true
        serviceMonitor = {
          enabled  = true
          interval = "30s"
          labels = {
            release = "kube-prometheus-stack"
          }
        }
      }

      operator = {
        prometheus = {
          enabled = true
          serviceMonitor = {
            enabled  = true
            interval = "30s"
            labels = {
              release = "kube-prometheus-stack"
            }
          }
        }
      }
    })
  ]
  depends_on = [kubectl_manifest.gateway_api_crds]
}

resource "kubectl_manifest" "cilium_ip_pool" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = "homelab-pool"
    }
    spec = {
      blocks = [
        {
          cidr = data.terraform_remote_state.network.outputs.athena_lb_cidr
        }
      ]
    }
  })

  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "cilium_l2_policy" {
  yaml_body = yamlencode({
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata = {
      name = "homelab-l2-policy"
    }
    spec = {
      nodeSelector = {
        matchExpressions = [] # Selects all nodes
      }
      interfaces      = ["eth0", "end0", "ens18"]
      externalIPs     = true
      loadBalancerIPs = true
    }
  })

  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "hubble_ui_http_route" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "hubble-ui"
      namespace = "kube-system"
    }
    spec = {
      parentRefs = [
        {
          name        = "main-gateway"
          namespace   = kubernetes_namespace_v1.gateway.metadata[0].name
          sectionName = "https"
        }
      ]
      hostnames = [
        "hubble.lippok.dev"
      ]
      rules = [
        {
          backendRefs = [
            {
              name = "hubble-ui"
              port = 80
            }
          ]
        }
      ]
    }
  })

  depends_on = [
    helm_release.cilium,
    kubectl_manifest.main_gateway
  ]
}

data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each  = data.kubectl_file_documents.gateway_api_crds.manifests
  yaml_body = each.value
}
