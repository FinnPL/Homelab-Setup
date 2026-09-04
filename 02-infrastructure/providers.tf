terraform {
  required_version = ">= 1.9.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.112.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.10.1"
    }
  }
}

provider "talos" {}
