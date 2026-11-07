# FPLNET gateway gw1-aah1

locals {
  # Built from the gw1-aah1 flake output (system.build.tarball) and uploaded by hand once.
  gw1_aah1_template = "${var.proxmox_iso_storage}:vztmpl/${var.gw1_aah1_config.template}"
}

# Unprivileged containers cannot load modules, and nftables only autoloads in the host namespace.
resource "proxmox_virtual_environment_file" "gw1_aah1_hookscript" {
  content_type = "snippets"
  datastore_id = var.proxmox_snippets_storage
  node_name    = var.proxmox_node
  file_mode    = "0700"

  source_raw {
    file_name = "gw1-aah1-hook.sh"
    data      = <<-EOT
      #!/bin/sh
      [ "$2" = "pre-start" ] || exit 0
      exec modprobe -a wireguard nf_tables nft_ct nft_fib_inet nft_reject_inet
    EOT
  }
}

resource "proxmox_virtual_environment_container" "gw1_aah1" {
  description = "FPLNET gateway gw1.aah1.fplnet.net"

  node_name = var.proxmox_node
  vm_id     = var.gw1_aah1_config.vmid

  cpu {
    cores = var.gw1_aah1_config.cores
  }

  memory {
    dedicated = var.gw1_aah1_config.memory
    swap      = 0
  }

  disk {
    datastore_id = var.proxmox_storage
    size         = var.gw1_aah1_config.disk_size
  }

  # Address, routes and hostname come from the NixOS config.
  network_interface {
    name        = "eth0"
    bridge      = var.proxmox_bridge
    firewall    = false
    mac_address = var.gw1_aah1_config.mac
  }

  operating_system {
    template_file_id = local.gw1_aah1_template
    type             = "unmanaged"
  }

  startup {
    order = "1"
  }

  features {
    nesting = true
  }

  started             = true
  unprivileged        = true
  hook_script_file_id = proxmox_virtual_environment_file.gw1_aah1_hookscript.id

  tags = sort(["terraform", "fplnet", "nixos"])

  lifecycle {
    # deploy-rs updates the system in place; a new template only matters on recreate.
    ignore_changes = [operating_system[0].template_file_id]
  }
}
