terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.120.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${local.minerva.pve}:8006"
  api_token = var.proxmox_api_token
  insecure  = true
}
