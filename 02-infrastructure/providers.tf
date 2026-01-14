terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.93.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.10.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "talos" {}

provider "github" {
  token = var.github_pat
  owner = var.github_owner
}
