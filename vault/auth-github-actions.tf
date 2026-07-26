resource "vault_jwt_auth_backend" "github_actions" {
  path               = "github-actions"
  description        = "GitHub Actions OIDC (one role per workflow)"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"
}

# Self-manages this vault TF config from CI.
resource "vault_jwt_auth_backend_role" "vault_deploy" {
  backend         = vault_jwt_auth_backend.github_actions.path
  role_name       = "vault-deploy"
  role_type       = "jwt"
  user_claim      = "job_workflow_ref"
  bound_audiences = [var.vault_address]

  bound_claims = {
    repository       = var.github_repository
    job_workflow_ref = "${var.github_repository}/.github/workflows/vault-deploy.yaml@refs/heads/main"
    environment      = "vault"
  }

  token_policies = [vault_policy.vault_deploy.name]
  token_type     = "service"
  token_ttl      = 1200
  token_max_ttl  = 1200
}
