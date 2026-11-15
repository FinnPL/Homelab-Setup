# The host's address comes from inventory/minerva.json.
locals {
  minerva = jsondecode(file("${path.module}/../../inventory/minerva.json")).inventory.minerva
}

variable "pve_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "proxmox_api_token" {
  description = "API token terraform@pve!minerva (kv/minerva/proxmox api-token): guests in the pool minerva, never the NAS VM"
  type        = string
  sensitive   = true
}
