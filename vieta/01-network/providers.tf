terraform {
  required_version = ">= 1.9.0"

  required_providers {
    unifi = {
      source  = "ubiquiti-community/unifi"
      version = "0.65.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.29.0"
    }
  }
}

provider "unifi" {
  api_key        = var.unifi_api_key
  api_url        = var.unifi_api_url
  allow_insecure = var.unifi_insecure
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
