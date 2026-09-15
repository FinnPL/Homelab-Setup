terraform {
  required_version = ">= 1.10.0"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "5.11.0"
    }
  }
}

provider "vault" {
  address          = var.vault_address
  skip_child_token = true
}

provider "tailscale" {
  tailnet         = var.tailnet
  oauth_client_id = var.oauth_client_id
  audience        = var.audience
}
