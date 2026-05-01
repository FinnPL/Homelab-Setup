resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

locals {
  argocd_oidc_config = yamlencode({
    name            = "Authentik"
    issuer          = "https://auth.lippok.dev/application/o/argocd/"
    clientID        = "argocd"
    clientSecret    = "$oidc.authentik.clientSecret"
    requestedScopes = ["openid", "profile", "email", "groups"]
  })
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.11"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      global = {
        logging = {
          level = "warn"
        }
      }
      server = {
        extraArgs = ["--insecure"]
      }
      configs = {
        params = {
          "server.insecure" = "true"
        }
        cm = {
          "url"         = "https://argocd.lippok.dev"
          "oidc.config" = local.argocd_oidc_config
        }
        rbac = {
          "policy.csv"     = "g, authentik Admins, role:admin"
          "policy.default" = "role:readonly"
          "scopes"         = "[groups]"
        }
      }
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
        initContainers = [
          {
            name    = "fix-nfs-permissions"
            image   = "busybox"
            command = ["sh", "-c", "chown 999:999 /nfs-tmp && chmod 777 /nfs-tmp"]
            volumeMounts = [
              {
                name      = "nfs-tmp"
                mountPath = "/nfs-tmp"
              }
            ]
            securityContext = {
              runAsUser = 0
            }
          }
        ]
      }

      applicationSet = {
        enabled = true
      }

      notifications = {
        enabled = true

        secret = {
          create = false # managed by charts/argocd/notifications-secret.yaml (ExternalSecret)
        }

        notifiers = {
          "service.webhook.github"  = <<-YAML
            url: https://api.github.com
            headers:
              - name: Authorization
                value: "token $github-token"
              - name: Content-Type
                value: application/json
          YAML
          "service.webhook.discord" = <<-YAML
            url: $discord-webhook
          YAML
        }

        triggers = {
          "trigger.on-sync-running"    = <<-YAML
            - when: app.spec.source.repoURL contains 'github.com' && app.status.operationState != nil && app.status.operationState.phase in ['Running']
              send: [github-commit-status]
          YAML
          "trigger.on-sync-succeeded"  = <<-YAML
            - when: app.spec.source.repoURL contains 'github.com' && app.status.operationState.phase in ['Succeeded'] && app.status.health.status == 'Healthy'
              send: [github-commit-status]
          YAML
          "trigger.on-sync-failed"     = <<-YAML
            - when: app.spec.source.repoURL contains 'github.com' && app.status.operationState.phase in ['Error', 'Failed']
              send: [github-commit-status]
          YAML
          "trigger.on-health-degraded" = <<-YAML
            - when: app.spec.source.repoURL contains 'github.com' && app.status.health.status == 'Degraded'
              send: [github-commit-status]
          YAML
          "trigger.on-app-failed"      = <<-YAML
            - when: app.status.operationState.phase in ['Error', 'Failed'] || app.status.health.status == 'Degraded'
              send: [discord-alert]
          YAML
        }

        templates = {
          "template.github-commit-status" = <<-YAML
            webhook:
              github:
                method: POST
                path: /repos/{{call .repo.FullNameByRepoURL .app.spec.source.repoURL}}/statuses/{{.app.status.operationState.operation.sync.revision}}
                body: |
                  {
                    "state": "{{if eq .app.status.operationState.phase "Running"}}pending{{else if and (eq .app.status.operationState.phase "Succeeded") (eq .app.status.health.status "Healthy")}}success{{else}}failure{{end}}",
                    "description": "{{if eq .app.status.operationState.phase "Running"}}Syncing…{{else if and (eq .app.status.operationState.phase "Succeeded") (eq .app.status.health.status "Healthy")}}Healthy{{else if eq .app.status.health.status "Degraded"}}Health degraded{{else}}Sync failed{{end}}",
                    "target_url": "https://argocd.lippok.dev/applications/{{.app.metadata.name}}",
                    "context": "argocd/{{.app.metadata.name}}"
                  }
          YAML
          "template.discord-alert"        = <<-YAML
            webhook:
              discord:
                method: POST
                path: /
                body: |
                  {
                    "content": "**ArgoCD** `{{.app.metadata.name}}` — {{if eq .app.status.operationState.phase "Error"}}Sync error: {{.app.status.operationState.message}}{{else if eq .app.status.operationState.phase "Failed"}}Sync failed: {{.app.status.operationState.message}}{{else}}Health degraded ({{.app.status.health.status}}){{end}}\n<https://argocd.lippok.dev/applications/{{.app.metadata.name}}>"
                  }
          YAML
        }

        subscriptions = [
          {
            recipients = ["github"]
            triggers   = ["on-sync-running", "on-sync-succeeded", "on-sync-failed", "on-health-degraded"]
          },
          {
            recipients = ["discord"]
            triggers   = ["on-app-failed"]
          }
        ]
      }
    })
  ]

  depends_on = [kubernetes_storage_class_v1.nfs, helm_release.cilium]
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

# Root Application for App of Apps pattern
resource "kubectl_manifest" "argocd_root_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/FinnPL/Homelab-Setup.git"
        targetRevision = "main"
        path           = "apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  })

  depends_on = [helm_release.argocd]
}
