# Groups carried in the Organization of Vault pki-k8s certificates.
resource "kubernetes_cluster_role_binding_v1" "homelab_admins" {
  metadata {
    name = "homelab-admins"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "homelab:admins"
  }
}

resource "kubernetes_cluster_role_v1" "homelab_reader" {
  metadata {
    name = "homelab-reader"
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["get"]
  }
}

resource "kubernetes_cluster_role_binding_v1" "homelab_readers" {
  metadata {
    name = "homelab-readers"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.homelab_reader.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Group"
    name      = "homelab:readers"
  }
}
