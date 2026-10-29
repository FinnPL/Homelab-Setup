locals {
  cluster_endpoint = "https://${local.talos_controlplane_ip}:6443"

  talos_versions     = yamldecode(file("${path.module}/talos-versions.yaml"))
  talos_version      = local.talos_versions.talos
  kubernetes_version = local.talos_versions.kubernetes

  # Pi workers with IPs from 01-network
  talos_workers = {
    for idx, ip in local.talos_worker_ips : "talos-worker-${idx + 1}" => ip
  }
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
  }
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = local.talos_version
  kubernetes_version = local.kubernetes_version

  config_patches = concat(local.talos_base_patches, [
    local.talos_install_patch.vm,
    local.talos_nic_patch.vm,
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeProxyConfig"
      enabled    = false
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeControllerManagerConfig"
      extraArgs = {
        "bind-address" = "0.0.0.0"
        "secure-port"  = "10257"
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeSchedulerConfig"
      extraArgs = {
        "bind-address" = "0.0.0.0"
        "secure-port"  = "10259"
      }
    }),
    yamlencode({
      cluster = {
        etcd = {
          extraArgs = {
            "listen-metrics-urls" = "http://0.0.0.0:2381"
          }
        }
      }
    }),
  ])
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
