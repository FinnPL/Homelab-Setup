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

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = var.proxmox_iso_storage
  node_name    = var.proxmox_node

  file_name = "talos-${var.talos_version}-amd64.iso"
  url       = var.talos_schematic_id != "" ? "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/metal-amd64.iso" : "https://github.com/siderolabs/talos/releases/download/${var.talos_version}/metal-amd64.iso"

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
