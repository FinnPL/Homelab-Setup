resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.0"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      redis = {
        enabled = false
      }

      redis-ha = {
        enabled = true
        persistence = {
          enabled      = true
          storageClass = "nfs-client"
          size         = "1Gi"
        }
        haproxy = {
          metrics = {
             enabled = false 
          }
        }
      }

      repoServer = {
        persistence = {
          enabled      = true
          storageClass = "nfs-client"
          size         = "2Gi"
        }
      }

      applicationSet = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_storage_class_v1.nfs]
}
