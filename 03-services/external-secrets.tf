# Temporary backend: Kubernetes namespace "secret-store"
# Future backend:    HashiCorp Vault
#
# Migration to Vault requires:
#   1. Update ClusterSecretStore provider block (kubernetes -> vault)
#   2. Update remoteRef.key in ExternalSecrets to Vault paths e.g., "authentik-config" -> "apps/authentik/config"
#   3. Remove secret-store namespace, RBAC, and seed secrets below

resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.0.1"
  namespace  = kubernetes_namespace_v1.external_secrets.metadata[0].name
  timeout    = 600

  values = [
    yamlencode({
      installCRDs = true
    })
  ]

  depends_on = [helm_release.cilium]
}

# Temporary Secret Store Backend that ESO reads from.

resource "kubernetes_namespace_v1" "secret_store" {
  metadata {
    name = "secret-store"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "purpose"                      = "eso-temporary-backend"
    }
  }
}

resource "kubernetes_service_account_v1" "eso_store_reader" {
  metadata {
    name      = "eso-store-reader"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
  }
}

resource "kubernetes_role_v1" "eso_secret_reader" {
  metadata {
    name      = "eso-secret-reader"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding_v1" "eso_secret_reader" {
  metadata {
    name      = "eso-secret-reader"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.eso_secret_reader.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.eso_store_reader.metadata[0].name
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
  }
}

resource "kubernetes_role_v1" "eso_token_requester" {
  metadata {
    name      = "eso-token-requester"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["serviceaccounts/token"]
    resource_names = [kubernetes_service_account_v1.eso_store_reader.metadata[0].name]
    verbs          = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "eso_token_requester" {
  metadata {
    name      = "eso-token-requester"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.eso_token_requester.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "external-secrets"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  }
}

# ClusterSecretStore
# When migrating to Vault, only this resource's provider block changes.

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "cluster-secret-store"
    }
    spec = {
      provider = {
        kubernetes = {
          remoteNamespace = kubernetes_namespace_v1.secret_store.metadata[0].name
          server = {
            url = "https://kubernetes.default.svc"
            caProvider = {
              type      = "ConfigMap"
              name      = "kube-root-ca.crt"
              key       = "ca.crt"
              namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
            }
          }
          auth = {
            serviceAccount = {
              name      = kubernetes_service_account_v1.eso_store_reader.metadata[0].name
              namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

# Seed Secrets (Temporary Backend Data)

resource "kubernetes_secret_v1" "seed_authentik_config" {
  metadata {
    name      = "authentik-config"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "secret-key" = var.authentik_secret_key
  }
}

resource "kubernetes_secret_v1" "seed_argocd_oidc" {
  metadata {
    name      = "argocd-oidc"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "client-secret" = var.argocd_oidc_client_secret
  }
}

resource "kubernetes_secret_v1" "seed_grafana_oidc" {
  metadata {
    name      = "grafana-oidc"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "client-secret" = var.grafana_oidc_client_secret
  }
}

resource "kubernetes_secret_v1" "seed_tailscale_oauth" {
  metadata {
    name      = "tailscale-oauth"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "oauth-client-id" = var.tailscale_oauth_client_id
    "oauth-secret"    = var.tailscale_oauth_secret
  }
}

resource "random_password" "cnpg_superuser" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "seed_cnpg_superuser" {
  metadata {
    name      = "cnpg-superuser"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    username = "postgres"
    password = random_password.cnpg_superuser.result
    endpoint = "cnpg-cluster-rw.cnpg-system.svc.cluster.local"
    port     = "5432"
  }
}

resource "kubernetes_secret_v1" "seed_gatus_discord" {
  metadata {
    name      = "gatus-discord"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "webhook-url" = var.gatus_discord_webhook_url
  }
}

resource "kubernetes_secret_v1" "seed_alertmanager_discord" {
  metadata {
    name      = "alertmanager-discord"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "webhook-url" = var.alertmanager_discord_webhook_url
  }
}

resource "kubernetes_secret_v1" "seed_proxmox_exporter" {
  metadata {
    name      = "proxmox-exporter"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "user"       = data.terraform_remote_state.infrastructure.outputs.proxmox_exporter_credentials.user
    "token-name" = data.terraform_remote_state.infrastructure.outputs.proxmox_exporter_credentials.token_name
    "token-value" = trimprefix(
      data.terraform_remote_state.infrastructure.outputs.proxmox_exporter_credentials.token_value,
      "${data.terraform_remote_state.infrastructure.outputs.proxmox_exporter_credentials.user}!${data.terraform_remote_state.infrastructure.outputs.proxmox_exporter_credentials.token_name}="
    )
  }
}

resource "kubernetes_secret_v1" "seed_unifi_exporter" {
  metadata {
    name      = "unifi-exporter"
    namespace = kubernetes_namespace_v1.secret_store.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    "username" = var.unifi_exporter_username
    "password" = var.unifi_exporter_password
  }
}
