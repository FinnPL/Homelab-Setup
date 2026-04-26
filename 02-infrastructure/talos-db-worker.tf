# Temporary worker for DB and other block-storage workloads until NAS iSCSI/NFS replaces this node and the Proxmox NFS server.
locals {
  talos_db_worker_ip = try(local.host_ips.talos_worker_6, null)
}

data "talos_machine_configuration" "db_worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  config_patches = [
    yamlencode({
      machine = {
        nodeLabels = {
          "dedicated" = "database"
        }
        kubelet = {
          extraArgs = {
            "register-with-taints" = "dedicated=database:NoSchedule"
          }
          extraMounts = [
            {
              destination = "/var/lib/local-path-provisioner"
              type        = "bind"
              source      = "/var/lib/local-path-provisioner"
              options     = ["bind", "rshared", "rw"]
            }
          ]
        }
        features = {
          kubePrism = {
            enabled = true
            port    = 7445
          }
        }
        install = {
          image = "factory.talos.dev/installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"
        }
      }
    }),
    yamlencode({
      cluster = {
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
      }
    }),
    yamlencode({
      machine = {
        logging = {
          destinations = [
            {
              endpoint = "udp://127.0.0.1:5140"
              format   = "json_lines"
            }
          ]
        }
        network = {
          interfaces = [
            {
              interface = "ens18"
              dhcp      = true
            }
          ]
        }
      }
    })
  ]
}

resource "proxmox_virtual_environment_vm" "talos_db_worker" {
  name      = var.talos_db_worker_config.name
  node_name = var.proxmox_node
  vm_id     = var.talos_db_worker_config.vmid

  description = <<-EOT
    Talos Kubernetes Worker (DB) - Managed by Terraform
    IP: ${local.talos_db_worker_ip}
    Cluster: ${var.cluster_name}
    Network: Athena VLAN ${local.athena_vlan_id}
  EOT
  tags        = ["terraform", "talos", "kubernetes", "worker", "db"]

  on_boot = true
  started = true

  machine = "q35"
  bios    = "ovmf"

  boot_order = ["scsi0", "ide0"]

  cpu {
    cores   = var.talos_db_worker_config.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.talos_db_worker_config.memory
  }

  efi_disk {
    datastore_id      = var.proxmox_storage
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  disk {
    datastore_id = var.proxmox_storage
    file_format  = "raw"
    interface    = "scsi0"
    size         = var.talos_db_worker_config.disk_size
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
    mac_address = local.host_vm_macs.talos_worker_6
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

resource "talos_machine_configuration_apply" "db_worker" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.db_worker.machine_configuration
  node                        = local.talos_db_worker_ip
  endpoint                    = local.talos_db_worker_ip

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.talos_db_worker]
  }

  depends_on = [
    talos_machine_bootstrap.this,
    proxmox_virtual_environment_vm.talos_db_worker
  ]
}
