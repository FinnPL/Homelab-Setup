resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = "1.15.1"
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
      interfaces      = ["eth0", "end0"]
      externalIPs     = true
      loadBalancerIPs = true
    }
  })

  depends_on = [helm_release.cilium]
}

data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = {
    for index, manifest in split("---", data.http.gateway_api_crds.response_body) :
    index => manifest
    if trimspace(manifest) != ""
  }
  yaml_body = each.value
}