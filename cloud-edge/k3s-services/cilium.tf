resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"
  timeout    = 600

  values = [
    yamlencode({
      kubeProxyReplacement = "true"
      k8sServiceHost       = "127.0.0.1"
      k8sServicePort       = 6443
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
        apiserver = {
          service = {
            type = "NodePort"
          }
        }
      }

      gatewayAPI = {
        enabled = true
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
