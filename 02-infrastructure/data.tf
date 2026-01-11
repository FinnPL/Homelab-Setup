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
  host_macs      = try(data.terraform_remote_state.network.outputs.host_macs, {})

  # Derived values
  proxmox_host_ip    = local.host_ips.nuc
  athena_gateway     = local.athena_network.gateway
  athena_vlan_id     = local.athena_network.vlan_id
  athena_subnet      = local.athena_network.subnet
  athena_subnet_cidr = split("/", local.athena_subnet)[1]

  # IP assignments sourced from 01-network outputs (DHCP reservations)
  windows_server_ip     = local.host_ips.windows_server
  github_runner_ip      = local.host_ips.github_runner
  talos_controlplane_ip = local.host_ips.talos_controlplane
  nfs_server_ip         = cidrhost(local.athena_subnet, 80)

  talos_worker_ips = [
    cidrhost(local.athena_subnet, 61),
    cidrhost(local.athena_subnet, 62),
    cidrhost(local.athena_subnet, 63),
    cidrhost(local.athena_subnet, 64),
    cidrhost(local.athena_subnet, 65),
  ]

  # Resolve MACs from 01-network outputs
  talos_controlplane_mac = local.host_macs.talos_controlplane
  github_runner_mac      = local.host_macs.github_runner
  windows_server_mac     = local.host_macs.windows_server

}
