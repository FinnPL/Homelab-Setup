terraform {
  required_providers {
    unifi = {
      source  = "filipowm/unifi"
      version = "~> 1.0.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
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
