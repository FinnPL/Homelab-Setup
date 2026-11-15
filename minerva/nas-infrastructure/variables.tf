# The addresses of the host and the NAS come from inventory/minerva.json.
locals {
  minerva = jsondecode(file("${path.module}/../../inventory/minerva.json")).inventory.minerva
}

variable "pve_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "proxmox_api_token" {
  description = "API token of terraform-nas@pve, minted per run by tf.sh over a YubiKey SSH login and revoked afterwards; never stored, never in CI"
  type        = string
  sensitive   = true
}

variable "nas_vm" {
  description = "The NAS VM, which owns the nas pool through the passed-through HBA"
  type = object({
    vmid      = number
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 110
    cores     = 4
    memory    = 6144
    disk_size = 32
  }
}

variable "bootstrap_image" {
  description = "Debian cloud image the VM first boots, downloaded by ../02-infrastructure (images.tf); only read at create"
  type        = string
  default     = "local:import/debian-13-genericcloud-amd64-20261103-2651.qcow2"
}
