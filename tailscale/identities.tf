locals {
  github_issuer = "https://token.actions.githubusercontent.com"
  subject       = "repo:${var.github_repository}:environment:%s"
}

# Runners that join the tailnet to reach the homelab: _terraform-layer.yaml and vieta job of ssh-cert-converge.yaml.
resource "tailscale_federated_identity" "vieta" {
  description = "GitHub Actions vieta environment"
  issuer      = local.github_issuer
  subject     = format(local.subject, "vieta")
  scopes      = ["auth_keys"]
  tags        = ["tag:ci"]
}

# Mints the edge node's own join key. The runner itself never joins the tailnet.
resource "tailscale_federated_identity" "cloud_edge" {
  description = "GitHub Actions cloud-edge environment"
  issuer      = local.github_issuer
  subject     = format(local.subject, "cloud-edge")
  scopes      = ["auth_keys"]
  tags        = ["tag:cloud-edge"]
}

resource "tailscale_federated_identity" "minerva" {
  description = "GitHub Actions minerva environment"
  issuer      = local.github_issuer
  subject     = format(local.subject, "minerva")
  scopes      = ["auth_keys"]
  tags        = ["tag:minerva"]
}

# The k8s operator mints a key per device continuously, so it needs a standing credential.
resource "tailscale_oauth_client" "vieta_operator" {
  description = "Vieta tailscale-operator"
  scopes      = ["auth_keys", "devices:core"]

  # Both names until charts/tailscale has rolled out, so this module and the chart can
  # be applied in either order without the operator losing the ability to mint keys.
  tags = ["tag:vieta-k8s", "tag:k8s"]
}

# Handed to the operator through Vault kv -> ESO
resource "vault_kv_secret_v2" "operator_oauth" {
  mount = "kv"
  name  = "apps/tailscale"

  data_json = jsonencode({
    oauth-client-id = tailscale_oauth_client.vieta_operator.id
    oauth-secret    = tailscale_oauth_client.vieta_operator.key
  })
}

output "federated_identity_client_ids" {
  description = "Set these as repo variables so the workflows can authenticate"
  value = {
    vieta      = tailscale_federated_identity.vieta.id
    cloud_edge = tailscale_federated_identity.cloud_edge.id
    minerva    = tailscale_federated_identity.minerva.id
  }
}
