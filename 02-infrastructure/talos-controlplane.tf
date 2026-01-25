locals {
  cluster_endpoint = "https://${local.talos_controlplane_ip}:6443"

  # Worker nodes with IPs from 01-network
  talos_workers = [
    for idx, enabled in var.talos_workers_enabled : {
      name       = "talos-worker-${idx + 1}"
      ip_address = local.talos_worker_ips[idx]
      enabled    = enabled
    }
  ]
}

resource "talos_machine_secrets" "this" {}

resource "proxmox_virtual_environment_vm" "talos_controlplane" {
  name      = var.talos_controlplane_config.name
  node_name = var.proxmox_node
  vm_id     = var.talos_controlplane_config.vmid

  description = <<-EOT
    Talos Kubernetes Control Plane - Managed by Terraform
    IP: ${local.talos_controlplane_ip}
    Cluster: ${var.cluster_name}
    Network: Athena VLAN ${local.athena_vlan_id}
  EOT
  tags        = ["terraform", "talos", "kubernetes", "controlplane"]

  on_boot = true
  started = true

  machine = "q35"
  bios    = "seabios"

  boot_order = ["scsi0", "ide0"]

  cpu {
    cores   = var.talos_controlplane_config.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.talos_controlplane_config.memory
  }

  disk {
    datastore_id = var.proxmox_storage
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.talos_controlplane_config.disk_size
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  cdrom {
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide0"
  }

  scsi_hardware = "virtio-scsi-single"

  network_device {
    bridge      = var.proxmox_bridge
    model       = "virtio"
    mac_address = local.talos_controlplane_mac
  }

  serial_device {}

  vga {
    type = "std"
  }

  agent {
    enabled = true
    type    = "virtio"
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      started,
    ]
    replace_triggered_by = [
      proxmox_virtual_environment_download_file.talos_iso.id
    ]
  }
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
        }
      }
    })
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.talos_controlplane_ip]
  nodes                = [local.talos_controlplane_ip]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  node                        = local.talos_controlplane_ip
  endpoint                    = local.talos_controlplane_ip

  depends_on = [
    proxmox_virtual_environment_vm.talos_controlplane
  ]

  lifecycle {
    replace_triggered_by = [
      proxmox_virtual_environment_vm.talos_controlplane.id
    ]
  }
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_controlplane_ip
  endpoint             = local.talos_controlplane_ip

  depends_on = [
    talos_machine_configuration_apply.controlplane
  ]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.talos_controlplane_ip
  endpoint             = local.talos_controlplane_ip

  depends_on = [
    talos_machine_bootstrap.this
  ]
}

output "talos_controlplane_vm" {
  description = "Talos control plane VM details"
  value = {
    vmid        = proxmox_virtual_environment_vm.talos_controlplane.vm_id
    name        = proxmox_virtual_environment_vm.talos_controlplane.name
    ip_address  = local.talos_controlplane_ip
    mac_address = local.talos_controlplane_mac
    endpoint    = local.cluster_endpoint
  }
}
