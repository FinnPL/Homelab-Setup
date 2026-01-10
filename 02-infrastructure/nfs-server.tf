# Provides persistent storage for Kubernetes workloads via NFS

resource "proxmox_virtual_environment_container" "nfs_server" {
  description = "NFS server for Kubernetes persistent volumes"

  node_name = var.proxmox_node
  vm_id     = var.nfs_server_config.vmid

  initialization {
    hostname = var.nfs_server_config.name

    ip_config {
      ipv4 {
        address = "${local.nfs_server_ip}/${local.athena_subnet_cidr}"
        gateway = local.athena_gateway
      }
    }

    dns {
      servers = [local.athena_gateway]
    }

    user_account {
      password = var.nfs_root_password
    }
  }

  cpu {
    cores = var.nfs_server_config.cores
  }

  memory {
    dedicated = var.nfs_server_config.memory
  }

  # Root filesystem on SSD for OS
  disk {
    datastore_id = var.proxmox_storage
    size         = var.nfs_server_config.root_disk_size
  }

  # Mount the HDD storage for NFS exports
  mount_point {
    volume = "${var.nfs_hdd_storage}:${var.nfs_server_config.data_disk_size}"
    path   = "/srv/nfs"
  }

  network_interface {
    name     = "eth0"
    bridge   = var.proxmox_bridge
    firewall = false
  }

  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.debian_lxc_template.id
    type             = "debian"
  }

  startup {
    order = "1"
  }

  features {
    nesting = true
  }

  started      = true
  unprivileged = true

  tags = ["kubernetes", "storage", "nfs"]
}

resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  content_type = "vztmpl"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  file_name = "debian-12-standard_12.12-1_amd64.tar.zst"
  url       = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"

  overwrite = false
}
