resource "helm_release" "cilium" {
  name            = "cilium"
  repository      = "https://helm.cilium.io/"
  chart           = "cilium"
  version         = var.cilium_version
  namespace       = "kube-system"
  timeout         = 600
  replace         = true
  cleanup_on_fail = true

  values = [
    yamlencode({
      kubeProxyReplacement = "true"
      k8sServiceHost       = "127.0.0.1"
      k8sServicePort       = 6443
      devices              = "eth+ wg+"
      ipam = {
        mode = "kubernetes"
      }

      # Cluster identity for Cluster Mesh
      cluster = {
        name = "cloud-edge"
        id   = 2
      }

      # Cluster Mesh: enable apiserver for cross-cluster connectivity
      clustermesh = {
        useAPIServer = true
        config = {
          enabled = true
        }
        apiserver = {
          service = {
            # NodePort so it's reachable via the OCI public IP from homelab Cilium agents
            type     = "NodePort"
            nodePort = 32379
          }
        }
        mcsapi = {
          enabled = true
        }
      }

      gatewayAPI = {
        enabled = true
      }

      securityContext = {
        capabilities = {
          ciliumAgent = [
            "CHOWN",
            "KILL",
            "NET_ADMIN",
            "NET_RAW",
            "IPC_LOCK",
            "SYS_MODULE",
            "SYS_ADMIN",
            "SYS_RESOURCE",
            "DAC_OVERRIDE",
            "FOWNER",
            "SETGID",
            "SETUID",
            "SYSLOG",
            "NET_BIND_SERVICE"
          ]
        }
      }

      envoy = {
        securityContext = {
          capabilities = {
            envoy = [
              "NET_ADMIN",
              "SYS_ADMIN",
              "NET_BIND_SERVICE"
            ]
            keepCapNetBindService = true
          }
        }
      }

      l2announcements = {
        enabled = false
      }

      cgroup = {
        autoMount = {
          enabled = true
        }
        hostRoot = "/sys/fs/cgroup"
      }

      hubble = {
        enabled = true
        relay = {
          enabled = true
        }
        ui = {
          enabled = false
        }
        metrics = {
          enableOpenMetrics = true
          enabled = [
            "dns:query;ignoreAAAA",
            "drop",
            "tcp",
            "icmp"
          ]
        }
      }

      operator = {
        replicas = 1
      }
    })
  ]

  depends_on = [kubectl_manifest.gateway_api_crds]
}
