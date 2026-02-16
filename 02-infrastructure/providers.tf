terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.93.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.10"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.6"
    }
  }
}

provider "talos" {}

provider "aws" {
  region = var.aws_region
}

provider "github" {
  token = var.github_pat
  owner = var.github_owner
}
