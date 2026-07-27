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

  token_policies = [vault_policy.vault_deploy.name, vault_policy.aws_tfstate.name]
  token_type     = "service"
  token_ttl      = 1200
  token_max_ttl  = 1200
}

resource "vault_jwt_auth_backend_role" "vieta_layers" {
  backend         = vault_jwt_auth_backend.github_actions.path
  role_name       = "vieta-layers"
  role_type       = "jwt"
  user_claim      = "job_workflow_ref"
  bound_audiences = [var.vault_address]

  bound_claims_type = "glob"
  bound_claims = {
    repository       = var.github_repository
    job_workflow_ref = "${var.github_repository}/.github/workflows/_terraform-layer.yaml@*"
    environment      = "vieta"
  }

  token_policies = [vault_policy.aws_tfstate.name, vault_policy.vieta.name]
  token_type     = "service"
  token_ttl      = 1200
  token_max_ttl  = 1200
}

resource "vault_jwt_auth_backend_role" "cloud_edge" {
  backend         = vault_jwt_auth_backend.github_actions.path
  role_name       = "cloud-edge"
  role_type       = "jwt"
  user_claim      = "job_workflow_ref"
  bound_audiences = [var.vault_address]

  bound_claims_type = "glob"
  bound_claims = {
    repository       = var.github_repository
    job_workflow_ref = "${var.github_repository}/.github/workflows/cloud-edge-deploy.yaml@*"
    environment      = "cloud-edge"
  }

  token_policies = [vault_policy.aws_tfstate.name, vault_policy.cloud_edge.name]
  token_type     = "service"
  token_ttl      = 1200
  token_max_ttl  = 1200
}

resource "vault_jwt_auth_backend_role" "minerva" {
  backend         = vault_jwt_auth_backend.github_actions.path
  role_name       = "minerva"
  role_type       = "jwt"
  user_claim      = "job_workflow_ref"
  bound_audiences = [var.vault_address]

  bound_claims = {
    repository       = var.github_repository
    job_workflow_ref = "${var.github_repository}/.github/workflows/minerva-deploy.yaml@refs/heads/main"
    environment      = "minerva"
  }

  token_policies = [vault_policy.minerva.name]
  token_type     = "service"
  token_ttl      = 1200
  token_max_ttl  = 1200
}
