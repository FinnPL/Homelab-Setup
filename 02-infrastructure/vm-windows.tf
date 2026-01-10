resource "proxmox_virtual_environment_vm" "windows_server" {
  name      = var.windows_vm_config.name
  node_name = var.proxmox_node
  vm_id     = var.windows_vm_config.vmid

  description = <<-EOT
    Windows Server 2025 - Managed by Terraform
    IP: ${local.windows_server_ip}
    Network: Athena VLAN ${local.athena_vlan_id}
  EOT
  tags        = ["terraform", "windows", "server"]

  on_boot = true
  started = true

  machine = "q35"
  bios    = "ovmf"

  cpu {
    cores   = var.windows_vm_config.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.windows_vm_config.memory
  }

  efi_disk {
    datastore_id      = var.proxmox_storage
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  tpm_state {
    datastore_id = var.proxmox_storage
    version      = "v2.0"
  }

  disk {
    datastore_id = var.proxmox_storage
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.windows_vm_config.disk_size
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # VirtIO drivers ISO on ide3
  disk {
    datastore_id = var.proxmox_iso_storage
    file_id      = proxmox_virtual_environment_download_file.virtio_drivers.id
    interface    = "ide3"
    file_format  = "raw"
  }

  # Windows installation ISO
  cdrom {
    enabled   = true
    file_id   = "${var.proxmox_iso_storage}:iso/windows-server-2025.iso"
    interface = "ide2"
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge  = var.proxmox_bridge
    model   = "virtio"
    vlan_id = local.athena_vlan_id
  }

  vga {
    type   = "std"
    memory = 64
  }

  agent {
    enabled = true
    type    = "virtio"
  }

  operating_system {
    type = "win11"
  }

  lifecycle {
    ignore_changes = [
      cdrom,
      started,
    ]
  }
}

output "windows_server_vm" {
  description = "Windows Server 2025 VM details"
  value = {
    vmid       = proxmox_virtual_environment_vm.windows_server.vm_id
    name       = proxmox_virtual_environment_vm.windows_server.name
    ip_address = local.windows_server_ip
    gateway    = local.athena_gateway
    vlan_id    = local.athena_vlan_id
  }
}
