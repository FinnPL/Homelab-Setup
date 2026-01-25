data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "finnpl-homelab-tfstate-1766068376"
    key    = "01-network/terraform.tfstate"
    region = "eu-central-1"
  }
}

locals {
  # Network configuration from 01-network
  athena_network = data.terraform_remote_state.network.outputs.athena_network
  host_ips       = data.terraform_remote_state.network.outputs.host_ips
  host_vm_macs   = try(data.terraform_remote_state.network.outputs.host_vm_macs, {})

  # Derived values
  proxmox_host_ip    = local.host_ips.nuc
  athena_gateway     = local.athena_network.gateway
  athena_vlan_id     = local.athena_network.vlan_id
  athena_subnet      = local.athena_network.subnet
  athena_subnet_cidr = split("/", local.athena_subnet)[1]

  # IP assignments sourced from 01-network outputs (DHCP reservations)
  windows_server_ip     = local.host_ips.windows_server
  talos_controlplane_ip = local.host_ips.talos_controlplane
  github_runner_ip      = local.host_ips.github_runner
  nfs_server_ip         = local.host_ips.nfs_server

  talos_worker_ips = [for v in [
    try(local.host_ips.talos_worker_1, null),
    try(local.host_ips.talos_worker_2, null),
    try(local.host_ips.talos_worker_3, null),
    try(local.host_ips.talos_worker_4, null),
    try(local.host_ips.talos_worker_5, null),
  ] : v if v != null]

  # Resolve MACs from 01-network outputs
  talos_controlplane_mac = try(local.host_vm_macs.talos_controlplane, null)
  windows_server_mac     = try(local.host_vm_macs.windows_server, null)
  github_runner_mac      = try(local.host_vm_macs.github_runner, null)
  nfs_server_mac         = try(local.host_vm_macs.nfs_server, null)
}
