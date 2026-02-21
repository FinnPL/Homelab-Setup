resource "helm_release" "crossplane" {
  name             = "crossplane"
  repository       = "https://charts.crossplane.io/stable"
  chart            = "crossplane"
  version          = "2.2.0"
  namespace        = "crossplane-system"
  create_namespace = true
}

resource "kubectl_manifest" "provider_sql" {
  yaml_body = yamlencode({
    apiVersion = "pkg.crossplane.io/v1"
    kind       = "Provider"
    metadata = {
      name = "provider-sql-postgres"
    }
    spec = {
      package = "xpkg.upbound.io/crossplane-contrib/provider-sql:${var.crossplane_provider_sql_version}"
    }
  })
  depends_on = [helm_release.crossplane]
}

locals {
  postgres_infra = data.terraform_remote_state.infrastructure.outputs.postgres_server
}

resource "kubernetes_secret" "postgres_provider_creds" {
  metadata {
    name      = "postgres-creds"
    namespace = "crossplane-system"
  }
  data = {
    username = "postgres"
    password = local.postgres_infra.password
    endpoint = local.postgres_infra.ip
    port     = "5432"
  }
}

resource "kubectl_manifest" "postgres_provider_config" {
  yaml_body = yamlencode({
    apiVersion = "postgresql.sql.crossplane.io/v1alpha1"
    kind       = "ProviderConfig"
    metadata = {
      name = "default"
    }
    spec = {
      credentials = {
        source = "PostgreSQLConnectionSecret"
        connectionSecretRef = {
          namespace = "crossplane-system"
          name      = kubernetes_secret.postgres_provider_creds.metadata[0].name
          keys = {
            username = "username"
            password = "password"
            endpoint = "endpoint"
            port     = "port"
          }
        }
      }
      sslMode = "require"
    }
  })
  depends_on = [kubectl_manifest.provider_sql]
}