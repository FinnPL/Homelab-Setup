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
      keys     = [file(pathexpand(var.github_runner_ssh_public_key_path))]
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
    firewall = true
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
    mount   = ["nfs"]
  }

  started      = true
  unprivileged = false

  tags = ["kubernetes", "storage", "nfs"]

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "apt-get update",
      "apt-get install -y nfs-kernel-server",
      "mkdir -p /srv/nfs/kubernetes",
      "chown nobody:nogroup /srv/nfs/kubernetes",
      "chmod 777 /srv/nfs/kubernetes",
      "echo '/srv/nfs/kubernetes ${local.athena_subnet}(rw,sync,no_subtree_check,no_root_squash)' > /etc/exports",
      "systemctl enable --now nfs-kernel-server",
      "exportfs -ra"
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file(pathexpand(var.github_runner_ssh_private_key_path))
      host        = local.nfs_server_ip
      timeout     = "5m"
    }
  }
}

resource "proxmox_virtual_environment_download_file" "debian_lxc_template" {
  content_type = "vztmpl"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  file_name = "debian-12-standard_12.12-1_amd64.tar.zst"
  url       = "http://download.proxmox.com/images/system/debian-12-standard_12.12-1_amd64.tar.zst"

  overwrite = false
}
