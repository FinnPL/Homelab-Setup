# WireGuard subnet router for the cloud-edge and homelab relay path.

resource "terraform_data" "mesh_wg_peer_endpoint_marker" {
  triggers_replace = local.mesh_wg_peer_endpoint
}

resource "proxmox_virtual_environment_container" "mesh_router" {
  description = "WireGuard subnet router for clustermesh"

  node_name = var.proxmox_node
  vm_id     = var.mesh_router_config.vmid

  initialization {
    hostname = var.mesh_router_config.name

    ip_config {
      ipv4 {
        address = "${local.mesh_router_ip}/${local.athena_subnet_cidr}"
        gateway = local.athena_gateway
      }
    }

    dns {
      servers = [local.athena_gateway]
    }

    user_account {
      password = var.mesh_router_root_password
      keys = [
        <<-EOT
        ${trimspace(var.proxmox_ssh_public_key)}
        EOT
      ]
    }
  }

  cpu {
    cores = var.mesh_router_config.cores
  }

  memory {
    dedicated = var.mesh_router_config.memory
  }

  disk {
    datastore_id = var.proxmox_storage
    size         = var.mesh_router_config.disk_size
  }

  network_interface {
    name        = "eth0"
    bridge      = var.proxmox_bridge
    firewall    = true
    mac_address = local.mesh_router_mac
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
  unprivileged = false

  tags = sort(["terraform", "wireguard", "clustermesh"])

  lifecycle {
    replace_triggered_by = [terraform_data.mesh_wg_peer_endpoint_marker]
  }

  provisioner "local-exec" {
    command = <<-EOT
      ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
        -i '${local.mesh_router_ip},' \
        --private-key '${local_sensitive_file.ansible_ssh_key.filename}' \
        --user root \
        --extra-vars '{"wg_private_key":"${var.mesh_wg_private_key}","wg_peer_pubkey":"${var.mesh_wg_peer_pubkey}","wg_peer_endpoint":"${local.mesh_wg_peer_endpoint}","cloud_vcn_cidr":"${var.cloud_vcn_cidr}"}' \
        '${path.module}/ansible/mesh-router.yml'
    EOT
  }
}
