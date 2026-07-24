terraform {
  required_version = ">= 1.10.0"

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.10.1"
    }
  }
}

provider "vault" {
  address = var.vault_address
}
