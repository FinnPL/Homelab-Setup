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
  depends_on = [kubernetes_manifest.gateway_api_crd]
}

resource "kubernetes_manifest" "cilium_ip_pool" {
  manifest = {
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
  }

  depends_on = [helm_release.cilium]
}

resource "kubernetes_manifest" "cilium_l2_policy" {
  manifest = {
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
  }

  depends_on = [helm_release.cilium]
}

data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"
}

locals {
  gateway_crds = [
    for doc in split("\n---", data.http.gateway_api_crds.response_body) :
    yamldecode(doc)
    if length(trimspace(doc)) > 0
  ]
}

resource "kubernetes_manifest" "gateway_api_crd" {
  for_each = {
    for idx, doc in local.gateway_crds :
    "${doc.kind}_${doc.metadata.name}" => doc
  }

  manifest = each.value
}