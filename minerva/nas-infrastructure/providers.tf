terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.123.1"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://${local.minerva.pve}:8006"
  api_token = var.proxmox_api_token
  insecure  = true
}
