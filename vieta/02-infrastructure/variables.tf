# =============================================================================
# Proxmox Configuration
# =============================================================================

variable "proxmox_insecure" {
  description = "Skip TLS verification for Proxmox API (set to true for self-signed certs)"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH username for Proxmox host (used for file uploads)"
  type        = string
  default     = "root"
}

variable "proxmox_ssh_password" {
  description = "SSH password for Proxmox host"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Name of the Proxmox node"
  type        = string
  default     = "nuc"
}

variable "proxmox_bridge" {
  description = "Proxmox network bridge to use for VMs"
  type        = string
  default     = "vmbr0"
}

variable "ansible_ssh_key_file" {
  description = "Path to the SSH private key Ansible authenticates with"
  type        = string
}

variable "proxmox_exporter_user_id" {
  description = "Proxmox user ID for the exporter token (for example prometheus-exporter@pve)"
  type        = string
  default     = "prometheus-exporter@pve"
}

variable "proxmox_exporter_token_name" {
  description = "Token name created for the Proxmox exporter user"
  type        = string
  default     = "metrics"
}

variable "proxmox_exporter_role_id" {
  description = "Proxmox role assigned to the exporter user"
  type        = string
  default     = "PVEAuditor"
}

variable "proxmox_exporter_acl_path" {
  description = "ACL path for the exporter user permissions"
  type        = string
  default     = "/"
}

# =============================================================================
# Storage Configuration
# =============================================================================

variable "proxmox_storage" {
  description = "Proxmox storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "proxmox_iso_storage" {
  description = "Proxmox storage pool for ISO images"
  type        = string
  default     = "local"
}

variable "proxmox_snippets_storage" {
  description = "Proxmox storage pool for snippets (hook scripts)"
  type        = string
  default     = "local"
}

# =============================================================================
# Windows Server VM Configuration
# =============================================================================

variable "windows_vm_config" {
  description = "Windows Server 2025 VM configuration"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 100
    name      = "windows-server-2025"
    cores     = 4
    memory    = 4096
    disk_size = 100
  }
}

# =============================================================================
# Talos Kubernetes Configuration
# =============================================================================

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "homelab-k8s"
}

variable "talos_controlplane_config" {
  description = "Talos control plane VM configuration (IP comes from 01-network outputs)"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 200
    name      = "talos-controlplane"
    cores     = 4
    memory    = 5120
    disk_size = 20
  }
}

variable "talos_db_worker_config" {
  description = "Dedicated Talos DB worker VM configuration"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 206
    name      = "talos-worker-db"
    cores     = 2
    memory    = 5120
    disk_size = 60
  }
}

# =============================================================================
# NFS Server Configuration
# =============================================================================

variable "nfs_server_config" {
  description = "NFS server LXC container configuration"
  type = object({
    vmid           = number
    name           = string
    cores          = number
    memory         = number
    root_disk_size = number # OS on SSD
    data_disk_size = number # NFS data on HDD
  })
  default = {
    vmid           = 400
    name           = "nfs-server"
    cores          = 1
    memory         = 512
    root_disk_size = 8
    data_disk_size = 500
  }
}

variable "nfs_hdd_storage" {
  description = "Proxmox storage pool for NFS data (must be created from /dev/sda first)"
  type        = string
  default     = "hdd-data"
}

variable "nfs_root_password" {
  description = "Root password for the NFS LXC container"
  type        = string
  sensitive   = true
}

variable "gw1_aah1_config" {
  description = "FPLNET gateway LXC configuration"
  type = object({
    vmid      = number
    cores     = number
    memory    = number
    disk_size = number
    mac       = string
    template  = string
  })
  default = {
    vmid      = 495
    cores     = 1
    memory    = 512
    disk_size = 8
    mac       = "bc:24:11:00:00:95"
    template  = "gw1-aah1-nixos-26.05.tar.xz"
  }
}
