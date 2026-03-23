provider "proxmox" {
  endpoint = "https://${local.proxmox_host_ip}:8006"
  username = "${var.proxmox_ssh_user}@pam"
  password = var.proxmox_ssh_password
  insecure = var.proxmox_insecure

  ssh {
    agent    = false
    username = var.proxmox_ssh_user
    password = var.proxmox_ssh_password
  }
}

resource "proxmox_virtual_environment_user" "metrics_exporter" {
  user_id = var.proxmox_exporter_user_id
  enabled = true
  comment = "Managed by Terraform for Prometheus Proxmox exporter"

  acl {
    path      = var.proxmox_exporter_acl_path
    role_id   = var.proxmox_exporter_role_id
    propagate = true
  }
}

resource "proxmox_virtual_environment_user_token" "metrics_exporter" {
  user_id               = proxmox_virtual_environment_user.metrics_exporter.user_id
  token_name            = var.proxmox_exporter_token_name
  privileges_separation = false
  comment               = "Managed by Terraform for Prometheus Proxmox exporter"
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          "siderolabs/qemu-guest-agent"
        ]
      }
    }
  })
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  file_name = "talos-${var.talos_version}-nocloud-amd64.iso"
  url       = "https://factory.talos.dev/image/${talos_image_factory_schematic.this.id}/${var.talos_version}/nocloud-amd64.iso"

  overwrite = false
}

resource "proxmox_virtual_environment_download_file" "virtio_drivers" {
  content_type = "iso"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  file_name = "virtio-win-stable.iso"
  url       = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

  overwrite = false
}
