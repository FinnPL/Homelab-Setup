# WireGuard subnet router for the cloud-edge and homelab relay path.

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

  connection {
    type        = "ssh"
    user        = "root"
    private_key = var.proxmox_ssh_private_key
    host        = local.mesh_router_ip
    timeout     = "5m"
  }

  provisioner "file" {
    content = templatefile("${path.module}/templates/mesh-wg0.conf", {
      private_key    = var.mesh_wg_private_key
      peer_pubkey    = var.mesh_wg_peer_pubkey
      peer_endpoint  = var.mesh_wg_peer_endpoint
      cloud_vcn_cidr = var.cloud_vcn_cidr
    })
    destination = "/tmp/wg0.conf"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",

      # Enable IP forwarding
      "echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-mesh-router.conf",
      "sysctl -w net.ipv4.ip_forward=1",

      # Install WireGuard + iptables (LXC base image is minimal)
      "apt-get update",
      "apt-get install -y wireguard-tools iptables",

      # Write WireGuard config
      "mkdir -p /etc/wireguard",
      "mv /tmp/wg0.conf /etc/wireguard/wg0.conf",
      "chmod 600 /etc/wireguard/wg0.conf",

      # Enable and start WireGuard
      "systemctl enable --now wg-quick@wg0",

      # Masquerade traffic from the OCI VCN out to the LAN.
      "cat > /etc/systemd/system/wg-mesh-nat.service <<'EOF'",
      "[Unit]",
      "Description=Masquerade OCI VCN traffic to homelab LAN",
      "After=wg-quick@wg0.service network-online.target",
      "Wants=wg-quick@wg0.service network-online.target",
      "",
      "[Service]",
      "Type=oneshot",
      "RemainAfterExit=true",
      "ExecStart=/sbin/iptables -t nat -A POSTROUTING -s ${var.cloud_vcn_cidr} -o eth0 -j MASQUERADE",
      "ExecStop=/sbin/iptables -t nat -D POSTROUTING -s ${var.cloud_vcn_cidr} -o eth0 -j MASQUERADE",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "systemctl daemon-reload",
      "systemctl enable --now wg-mesh-nat.service",
    ]
  }
}
