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
  version    = "0.14.3"
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
    name      = "external-secrets"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
  }
}

# ClusterSecretStore
# When migrating to Vault, only this resource's provider block changes.

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
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
