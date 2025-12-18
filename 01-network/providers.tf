terraform {
  required_providers {
    unifi = {
      source  = "paultyng/unifi"
      version = "~> 0.41.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "unifi" {
  username       = var.unifi_username
  password       = var.unifi_password
  api_url        = var.unifi_api_url
  allow_insecure = var.unifi_insecure
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}