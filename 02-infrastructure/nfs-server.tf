# Provides persistent storage for Kubernetes workloads via NFS

resource "proxmox_virtual_environment_container" "nfs_server" {
  description = "NFS server for Kubernetes persistent volumes"

  node_name = var.proxmox_node
  vm_id     = var.nfs_server_config.vmid

  initialization {
    hostname = var.nfs_server_config.name
    user_account {
      password = var.nfs_root_password
      keys = [
        <<-EOT
        ${trimspace(var.proxmox_ssh_public_key)}
        EOT
      ]
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

  lifecycle {
    ignore_changes = [
      mount_point[0].volume,
      mount_point[0].size
    ]
  }

  network_interface {
    name        = "eth0"
    bridge      = var.proxmox_bridge
    firewall    = true
    mac_address = local.nfs_server_mac
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

  tags = sort(["kubernetes", "storage", "nfs", "terraform"])

  provisioner "local-exec" {
    command = <<-EOT
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i '${local.nfs_server_ip},' \
        --private-key '${local_sensitive_file.ansible_ssh_key.filename}' \
        --user root \
        --extra-vars 'nfs_export_subnet=${local.athena_subnet}' \
        '${path.module}/ansible/nfs-server.yml'
    EOT
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
