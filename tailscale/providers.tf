terraform {
  required_version = ">= 1.10.0"

  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.29.2"
    }
  }
}

provider "tailscale" {
  tailnet         = var.tailnet
  oauth_client_id = var.oauth_client_id
  audience        = var.audience
}
