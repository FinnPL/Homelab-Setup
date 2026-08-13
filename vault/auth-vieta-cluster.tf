# Vault has no network path into the homelab. Signing key is pinned here instead.
# Re-sync vieta-sa-pubkey.pem from `kubectl get --raw /openid/v1/jwks` on cluster rebuilt.
resource "vault_jwt_auth_backend" "vieta_cluster" {
  path                   = "vieta-cluster"
  description            = "Vieta Kubernetes service-account tokens"
  bound_issuer           = var.vieta_apiserver_issuer
  jwt_validation_pubkeys = [chomp(file("${path.module}/vieta-sa-pubkey.pem"))]
}

resource "vault_jwt_auth_backend_role" "eso" {
  backend         = vault_jwt_auth_backend.vieta_cluster.path
  role_name       = "eso"
  role_type       = "jwt"
  user_claim      = "sub"
  bound_audiences = ["vault"]

  bound_claims = {
    sub = "system:serviceaccount:external-secrets:external-secrets"
  }

  token_policies = [vault_policy.eso.name]
  token_type     = "service"
  token_ttl      = 600
  token_max_ttl  = 600
}

resource "vault_policy" "eso" {
  name = "eso"

  policy = <<-EOT
    path "kv/data/apps/*" { capabilities = ["read"] }
  EOT
}
