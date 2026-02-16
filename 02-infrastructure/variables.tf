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

# =============================================================================
# AWS Configuration
# =============================================================================

variable "aws_region" {
  description = "AWS region for infrastructure resources (Vault auto-unseal KMS key)"
  type        = string
  default     = "eu-central-1"
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

# =============================================================================
# GitHub Actions Runner Configuration
# =============================================================================

variable "github_pat" {
  description = "GitHub personal access token (needs repo/admin:org scope for runners)"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub user or organization that owns the repository"
  type        = string
  default     = "FinnPL"
}

variable "github_repository" {
  description = "GitHub repository name to register the runner against"
  type        = string
  default     = "Homelab-Setup"
}

variable "github_runner_template_vmid" {
  description = "Proxmox VMID of an existing Debian cloud-init template to clone for the runner"
  type        = number
  default     = 9000
}

variable "github_runner_config" {
  description = "Self-hosted runner VM settings"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 310
    name      = "github-runner-01"
    cores     = 2
    memory    = 2048
    disk_size = 40
  }
}

variable "github_runner_labels" {
  description = "Labels to assign to the GitHub self-hosted runner"
  type        = list(string)
  default     = ["proxmox", "docker", "self-hosted"]
}

variable "github_runner_version" {
  description = "GitHub Actions runner release version"
  type        = string
  # renovate: datasource=github-releases depName=actions/runner versioning=semver extractVersion=^v?(?<version>.*)$
  default = "2.331.0"
}

variable "github_runner_ssh_user" {
  description = "SSH user configured on the runner template"
  type        = string
  default     = "debian"
}

variable "github_runner_ssh_public_key_path" {
  description = "Path to the SSH public key used for cloud-init (authorized_keys)"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "github_runner_ssh_private_key_path" {
  description = "Path to the SSH private key used by the remote-exec provisioner"
  type        = string
  default     = "~/.ssh/id_rsa"
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

# =============================================================================
# Postgres Server Configuration
# =============================================================================

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

# =============================================================================
# Vault Server Configuration
# =============================================================================

variable "vault_server_config" {
  description = "HashiCorp Vault LXC configuration"
  type = object({
    vmid      = number
    name      = string
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    vmid      = 420
    name      = "vault"
    cores     = 2
    memory    = 2048
    disk_size = 10
  }
}

variable "vault_root_password" {
  description = "Root password for the Vault LXC"
  type        = string
  sensitive   = true
}

variable "vault_auto_unseal_kms_alias" {
  description = "AWS KMS alias used for Vault auto-unseal"
  type        = string
  default     = "alias/homelab-vault-auto-unseal"
}

variable "vault_auto_unseal_iam_user_name" {
  description = "IAM user name used by Vault for AWS KMS auto-unseal"
  type        = string
  default     = "vault-auto-unseal"
}