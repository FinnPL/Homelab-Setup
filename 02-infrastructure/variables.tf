# =============================================================================
# Proxmox Configuration
# =============================================================================

variable "proxmox_api_token" {
  description = "Proxmox API Token in format: user@realm!tokenid=token-secret"
  type        = string
  sensitive   = true
}

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

variable "proxmox_ssh_private_key" {
  description = "Raw SSH private key content for remote-exec"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_public_key" {
  description = "Raw SSH public key string for authorized_keys"
  type        = string
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

variable "windows_admin_password" {
  description = "Windows Server administrator password"
  type        = string
  sensitive   = true
}

variable "windows_product_key" {
  description = "Windows Server 2025 product key"
  type        = string
  sensitive   = true
  default     = ""
}

# =============================================================================
# Talos Kubernetes Configuration
# =============================================================================

variable "talos_version" {
  description = "Talos Linux version to use"
  type        = string
  # renovate: datasource=github-releases depName=siderolabs/talos
  default = "v1.12.1"
}

variable "kubernetes_version" {
  description = "Kubernetes version for Talos cluster"
  type        = string
  # renovate: datasource=github-releases depName=kubernetes/kubernetes versioning=semver extractVersion=^v(?<version>.*)$
  default = "1.35.0"
}

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
    memory    = 4096
    disk_size = 20
  }
}

variable "talos_workers_enabled" {
  description = "Enable flags for each worker node (indices 0-4 map to workers 1-5)"
  type        = list(bool)
  default     = [true, true, true, false, false]
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
    disk_size = 30
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

variable "postgres_server_config" {
  description = "Postgres LXC container configuration"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 410
    name      = "postgres-db"
    cores     = 2
    memory    = 2048
    disk_size = 10
  }
}

variable "postgres_root_password" {
  description = "Root password for the Postgres LXC OS"
  type        = string
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "Password for the database superuser"
  type        = string
  sensitive   = true
}