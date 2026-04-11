# WireGuard subnet router for Cilium clustermesh between homelab-k8s and cloud-edge.
# Forwards 10.70.1.0/24 traffic through a WG tunnel to the OCI node (public IP).
# No SNAT — VXLAN outer source IPs are preserved end-to-end.

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

  provisioner "remote-exec" {
    inline = [
      "set -e",

      # Enable IP forwarding
      "echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-mesh-router.conf",
      "sysctl --system",

      # Install WireGuard
      "apt-get update",
      "apt-get install -y wireguard-tools",

      # Write WireGuard config
      "mkdir -p /etc/wireguard",
      "cat > /etc/wireguard/wg0.conf << 'WGEOF'\n${templatefile("${path.module}/templates/mesh-wg0.conf", {
        private_key    = var.mesh_wg_private_key
        peer_pubkey    = var.mesh_wg_peer_pubkey
        peer_endpoint  = var.mesh_wg_peer_endpoint
        cloud_vcn_cidr = var.cloud_vcn_cidr
      })}\nWGEOF",
      "chmod 600 /etc/wireguard/wg0.conf",

      # Enable and start WireGuard
      "systemctl enable --now wg-quick@wg0",
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = var.proxmox_ssh_private_key
      host        = local.mesh_router_ip
      timeout     = "5m"
    }
  }
}
