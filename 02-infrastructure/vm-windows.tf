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
  started = false

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

  # Windows installation ISO
  cdrom {
    file_id   = "${var.proxmox_iso_storage}:iso/windows-server-2025.iso"
    interface = "ide2"
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge      = var.proxmox_bridge
    model       = "virtio"
    mac_address = local.windows_server_mac
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
    prevent_destroy = true
  }

  # Attach VirtIO ISO after creation (Proxmox allows only one cdrom in provider).
  provisioner "local-exec" {
    command = "sshpass -p '${var.proxmox_ssh_password}' ssh -o StrictHostKeyChecking=no ${var.proxmox_ssh_user}@${local.proxmox_host_ip} \"qm set ${var.windows_vm_config.vmid} -ide3 ${var.proxmox_iso_storage}:iso/virtio-win-stable.iso,media=cdrom\""
  }

  # Start VM after attaching VirtIO ISO
  provisioner "local-exec" {
    command = "sshpass -p '${var.proxmox_ssh_password}' ssh -o StrictHostKeyChecking=no ${var.proxmox_ssh_user}@${local.proxmox_host_ip} \"qm start ${var.windows_vm_config.vmid}\""
  }
}

output "windows_server_vm" {
  description = "Windows Server 2025 VM details"
  value = {
    vmid        = proxmox_virtual_environment_vm.windows_server.vm_id
    name        = proxmox_virtual_environment_vm.windows_server.name
    ip_address  = local.windows_server_ip
    mac_address = local.windows_server_mac
    gateway     = local.athena_gateway
    vlan_id     = local.athena_vlan_id
  }
}
