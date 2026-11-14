# The NAS VM.
# It boots the Debian cloud image (../02-infrastructure/images.tf) only once, then nixos-anywhere replaces it.

resource "proxmox_hardware_mapping_pci" "nas_hba" {
  name    = "nas-hba"
  comment = "SAS3008 HBA with the nas pool disks"
  map = [{
    node         = var.pve_node
    path         = "0000:01:00.0"
    id           = "1000:0097"
    subsystem_id = "1bd4:000c"
    iommu_group  = 10
  }]
}

resource "proxmox_virtual_environment_vm" "nas" {
  name        = "nas"
  node_name   = var.pve_node
  vm_id       = var.nas_vm.vmid
  description = "NixOS NAS (minerva/nixos), owns the nas pool. Managed by Terraform."
  tags        = ["terraform", "nixos", "nas"]

  on_boot             = true
  started             = true
  reboot_after_update = false

  machine = "q35"
  bios    = "ovmf"

  boot_order = ["scsi0"]

  cpu {
    cores = var.nas_vm.cores
    type  = "host"
  }

  memory {
    dedicated = var.nas_vm.memory
  }

  efi_disk {
    datastore_id      = "local-zfs"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = "local-zfs"
    import_from  = var.bootstrap_image
    interface    = "scsi0"
    size         = var.nas_vm.disk_size
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  scsi_hardware = "virtio-scsi-single"

  hostpci {
    device  = "hostpci0"
    mapping = proxmox_hardware_mapping_pci.nas_hba.name
    pcie    = true
  }

  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-zfs"
    ip_config {
      ipv4 {
        address = var.nas_vm.address
        gateway = var.nas_vm.gateway
      }
    }
    dns {
      servers = [var.nas_vm.gateway]
    }
    # The bootstrap image takes the same YubiKeys as the installed system.
    user_account {
      username = "debian"
      keys     = [for l in split("\n", file("${path.module}/../nixos/files/admin-keys.pub")) : l if l != "" && !startswith(l, "#")]
    }
  }

  serial_device {}

  agent {
    enabled = true
    # The Debian bootstrap image has no guest agent
    wait_for_ip {
      disabled = true
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    # Only the first boot used the image.
    ignore_changes = [disk[0].import_from]
  }
}
