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
        enabled = false
      }

      redis-ha = {
        enabled = true
        podSecurityContext = {
          fsGroup = 1000
        }
        securityContext = {
          runAsUser = 1000
        }
        persistentVolume = {
          enabled      = true
          storageClass = "nfs-client"
          size         = "1Gi"
        }
        initContainers = [
          {
            name    = "fix-permissions"
            image   = "alpine:3.18"
            command = ["/bin/sh", "-c"]
            args    = ["chown -R 1000:1000 /data"]
            volumeMounts = [
              {
                name      = "data"
                mountPath = "/data"
              }
            ]
            securityContext = {
              runAsUser = 0
            }
          }
        ]
        haproxy = {
          metrics = {
            enabled = false
          }
        }
      }

      repoServer = {
        volumes = [
          {
            name = "repo-server-tmp"
            emptyDir = {
              medium    = "Memory"
              sizeLimit = "1Gi"
            }
          }
        ]
        volumeMounts = [
          {
            name      = "repo-server-tmp"
            mountPath = "/tmp"
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
