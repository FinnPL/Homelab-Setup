terraform {
  required_version = ">= 1.9.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.01"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.1.1"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.0"
    }
  }
}