# The box sits on Vieta's Athena VLAN until it moves to Freiburg; pve_host changes with the move.

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
  description = "API token terraform@pve!minerva (kv/minerva/proxmox api-token): guests in the pool minerva, never the NAS VM"
  type        = string
  sensitive   = true
}
