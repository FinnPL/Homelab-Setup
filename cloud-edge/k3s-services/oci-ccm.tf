locals {
  cloud_edge  = data.terraform_remote_state.cloud_edge.outputs
  ccm_ns      = "kube-system"

  cloud_provider_config = yamlencode({
    auth = {
      region               = local.cloud_edge.oci_region
      useInstancePrincipals = true
    }
    compartment = local.cloud_edge.oci_compartment_ocid
    vcn         = local.cloud_edge.vcn_id
    loadBalancer = {
      subnet1                    = local.cloud_edge.subnet_id
      securityListManagementMode = "None"
    }
  })
}

resource "kubernetes_secret_v1" "ccm_config" {
  metadata {
    name      = "oci-cloud-controller-manager"
    namespace = local.ccm_ns
  }

  data = {
    "cloud-provider.yaml" = local.cloud_provider_config
  }
}

resource "kubernetes_service_account_v1" "ccm" {
  metadata {
    name      = "oci-cloud-controller-manager"
    namespace = local.ccm_ns
  }
}

resource "kubectl_manifest" "ccm_cluster_role" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = "system:cloud-controller-manager"
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["nodes"]
        verbs     = ["get", "list", "watch", "patch", "update"]
      },
      {
        apiGroups = [""]
        resources = ["nodes/status"]
        verbs     = ["patch"]
      },
      {
        apiGroups = [""]
        resources = ["services"]
        verbs     = ["get", "list", "watch", "patch", "update"]
      },
      {
        apiGroups = [""]
        resources = ["services/status"]
        verbs     = ["patch", "update"]
      },
      {
        apiGroups = [""]
        resources = ["events"]
        verbs     = ["create", "patch", "update"]
      },
      {
        apiGroups = [""]
        resources = ["endpoints"]
        verbs     = ["get", "list", "watch", "create", "update", "patch"]
      },
      {
        apiGroups = [""]
        resources = ["serviceaccounts"]
        verbs     = ["get"]
      },
      {
        apiGroups = [""]
        resources = ["configmaps"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["coordination.k8s.io"]
        resources = ["leases"]
        verbs     = ["get", "list", "watch", "create", "update", "patch", "delete"]
      },
      {
        apiGroups = ["discovery.k8s.io"]
        resources = ["endpointslices"]
        verbs     = ["get", "list", "watch"]
      },
    ]
  })
}

resource "kubectl_manifest" "ccm_cluster_role_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "system:cloud-controller-manager"
    }
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "system:cloud-controller-manager"
    }
    subjects = [
      {
        kind      = "ServiceAccount"
        name      = kubernetes_service_account_v1.ccm.metadata[0].name
        namespace = local.ccm_ns
      },
    ]
  })
}

resource "kubectl_manifest" "ccm_deployment" {
  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name      = "oci-cloud-controller-manager"
      namespace = local.ccm_ns
      labels = {
        "k8s-app" = "oci-cloud-controller-manager"
      }
    }
    spec = {
      replicas = 1
      selector = {
        matchLabels = {
          "k8s-app" = "oci-cloud-controller-manager"
        }
      }
      template = {
        metadata = {
          labels = {
            "k8s-app" = "oci-cloud-controller-manager"
          }
        }
        spec = {
          serviceAccountName = kubernetes_service_account_v1.ccm.metadata[0].name
          hostNetwork        = true
          tolerations = [
            {
              key    = "node.cloudprovider.kubernetes.io/uninitialized"
              value  = "true"
              effect = "NoSchedule"
            },
            {
              key      = "node-role.kubernetes.io/control-plane"
              operator = "Exists"
              effect   = "NoSchedule"
            },
          ]
          containers = [
            {
              name  = "oci-cloud-controller-manager"
              image = "ghcr.io/oracle/cloud-provider-oci:${var.oci_ccm_version}"
              command = [
                "/usr/local/bin/oci-cloud-controller-manager",
                "--cloud-config=/etc/oci/cloud-provider.yaml",
                "--cloud-provider=oci",
                "--leader-elect=false",
                "--v=2",
              ]
              volumeMounts = [
                {
                  name      = "cfg"
                  mountPath = "/etc/oci"
                  readOnly  = true
                },
              ]
            },
          ]
          volumes = [
            {
              name = "cfg"
              secret = {
                secretName = kubernetes_secret_v1.ccm_config.metadata[0].name
              }
            },
          ]
        }
      }
    }
  })

  depends_on = [
    kubectl_manifest.ccm_cluster_role_binding,
  ]
}
