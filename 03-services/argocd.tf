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

  set = [
    {
      name  = "redis.persistence.enabled"
      value = "true"
    },
    {
      name  = "redis.persistence.storageClass"
      value = "nfs-client"
    },
    {
      name  = "redis.persistence.size"
      value = "1Gi"
    },
    {
      name  = "applicationSet.enabled"
      value = "true"
    }
  ]

  depends_on = [kubernetes_storage_class_v1.nfs]
}
