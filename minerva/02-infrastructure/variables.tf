# The box sits on Vieta's Athena VLAN until it moves to Freiburg. pve_host and nas_vm.address
# change with the move, together with the address in ../nixos/hosts/nas/default.nix.

variable "pve_host" {
  description = "Address of the Minerva Proxmox host"
  type        = string
  default     = "10.10.1.10"
}

variable "pve_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve"
}

variable "proxmox_api_token" {
  description = "API token of root@pam (kv/minerva/proxmox api-token), privilege separation off"
  type        = string
  sensitive   = true
}

variable "nas_vm" {
  description = "The NAS VM, which owns the nas pool through the passed-through HBA"
  type = object({
    vmid      = number
    address   = string
    gateway   = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 110
    address   = "10.10.1.11/24"
    gateway   = "10.10.1.1"
    cores     = 4
    memory    = 6144
    disk_size = 32
  }
}
