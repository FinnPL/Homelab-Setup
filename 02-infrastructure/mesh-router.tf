# WireGuard subnet router for the cloud-edge and homelab relay path.

locals {
  mesh_router_extra_vars = jsonencode({
    wg_peer_pubkey           = var.mesh_wg_peer_pubkey
    wg_peer_endpoint         = local.mesh_wg_peer_endpoint
    cloud_vcn_cidr           = var.cloud_vcn_cidr
    cloud_edge_allowed_dests = var.cloud_edge_allowed_dests
    cloud_edge_allowed_port  = var.cloud_edge_allowed_port
  })
}

resource "proxmox_download_file" "debian_13_lxc_template" {
  content_type = "vztmpl"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  file_name = "debian-13-standard_13.6-1_amd64.tar.zst"

  # http://download.proxmox.com/images/aplinfo-pve-9.dat
  url                = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  checksum           = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  checksum_algorithm = "sha512"

  overwrite           = false
  overwrite_unmanaged = true
  upload_timeout      = 1800
}

resource "proxmox_virtual_environment_file" "mesh_router_hookscript" {
  content_type = "snippets"
  datastore_id = var.proxmox_snippets_storage
  node_name    = var.proxmox_node
  file_mode    = "0700"

  source_raw {
    file_name = "mesh-router-hook.sh"
    data      = <<-EOT
      #!/bin/sh
      [ "$2" = "pre-start" ] || exit 0
      exec modprobe -a wireguard nf_tables nft_compat nft_chain_nat nft_masq nft_ct xt_MASQUERADE xt_conntrack
    EOT
  }
}

resource "proxmox_virtual_environment_container" "mesh_router" {
  description = "WireGuard router for the cloud-edge tunnel"

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
      keys     = [local.vault_user_ca_authorized_key]
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
    template_file_id = proxmox_download_file.debian_13_lxc_template.id
    type             = "debian"
  }

  startup {
    order = "1"
  }

  features {
    nesting = true
  }

  started             = true
  unprivileged        = true
  hook_script_file_id = proxmox_virtual_environment_file.mesh_router_hookscript.id

  tags = sort(["terraform", "wireguard"])

  lifecycle {
    ignore_changes = [initialization[0].user_account[0].keys]
  }

  # First boot only
  provisioner "local-exec" {
    environment = {
      WG_PRIVATE_KEY = var.mesh_wg_private_key
    }
    command = <<-EOT
      ANSIBLE_HOST_KEY_CHECKING=True \
      ANSIBLE_SSH_EXTRA_ARGS='-o StrictHostKeyChecking=accept-new' \
      ansible-playbook \
        -i '${local.mesh_router_ip},' \
        --private-key '${var.ansible_ssh_key_file}' \
        --user root \
        --extra-vars '${local.mesh_router_extra_vars}' \
        '${path.module}/ansible/mesh-router.yml'
    EOT
  }
}

# Re-converges the running router when its inputs or playbook change.
resource "terraform_data" "mesh_router_config" {
  triggers_replace = [
    proxmox_virtual_environment_container.mesh_router.id,
    local.mesh_router_extra_vars,
    sha256(var.mesh_wg_private_key),
    filesha256("${path.module}/ansible/mesh-router.yml"),
    filesha256("${path.module}/ansible/templates/wg0.conf.j2"),
    filesha256("${path.module}/ansible/templates/wg-mesh-nat.service.j2"),
  ]

  provisioner "local-exec" {
    environment = {
      WG_PRIVATE_KEY = var.mesh_wg_private_key
    }
    command = <<-EOT
      ANSIBLE_HOST_KEY_CHECKING=True \
      ansible-playbook \
        -i '${local.mesh_router_ip},' \
        --private-key '${var.ansible_ssh_key_file}' \
        --user root \
        --skip-tags ssh-ca \
        --extra-vars '${local.mesh_router_extra_vars}' \
        '${path.module}/ansible/mesh-router.yml'
    EOT
  }
}
