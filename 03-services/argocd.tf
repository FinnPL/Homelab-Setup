resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.3.7"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      redis = {
        enabled = true
        volumes = [
          {
            name = "redis-data"
            emptyDir = {
              medium    = "Memory"
              sizeLimit = "1Gi"
            }
          }
        ]
        volumeMounts = [
          {
            name      = "redis-data"
            mountPath = "/data"
          }
        ]
      }

      "redis-ha" = {
        enabled = false
      }

      repoServer = {
        volumes = [
          {
            name = "nfs-tmp"
            persistentVolumeClaim = {
              claimName = kubernetes_persistent_volume_claim_v1.argocd_repo_server.metadata[0].name
            }
          }
        ]

        volumeMounts = [
          {
            name      = "nfs-tmp"
            mountPath = "/nfs-tmp"
          }
        ]

        env = [
          {
            name  = "TMPDIR"
            value = "/nfs-tmp"
          }
        ]
      }

      applicationSet = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_storage_class_v1.nfs]
}

resource "kubernetes_persistent_volume_claim_v1" "argocd_repo_server" {
  metadata {
    name      = "argocd-repo-server-nfs"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "nfs-client"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }

  depends_on = [kubernetes_storage_class_v1.nfs]
}
