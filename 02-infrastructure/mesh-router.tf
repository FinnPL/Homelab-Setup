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

  provisioner "file" {
    content = templatefile("${path.module}/templates/wg-mesh-nat.service", {
      cloud_vcn_cidr = var.cloud_vcn_cidr
    })
    destination = "/tmp/wg-mesh-nat.service"
  }

  provisioner "remote-exec" {
    inline = [
      "set -e",
      "echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-mesh-router.conf",
      "sysctl -w net.ipv4.ip_forward=1",
      "apt-get update",
      "apt-get install -y wireguard-tools iptables",
      "mkdir -p /etc/wireguard",
      "mv /tmp/wg0.conf /etc/wireguard/wg0.conf",
      "chmod 600 /etc/wireguard/wg0.conf",
      "systemctl enable --now wg-quick@wg0",
      "mv /tmp/wg-mesh-nat.service /etc/systemd/system/wg-mesh-nat.service",
      "chmod 644 /etc/systemd/system/wg-mesh-nat.service",
      "systemctl daemon-reload",
      "systemctl enable --now wg-mesh-nat.service",
    ]
  }
}
