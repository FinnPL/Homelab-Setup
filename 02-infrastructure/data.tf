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

  # Derived values
  proxmox_host_ip    = local.host_ips.nuc
  athena_gateway     = local.athena_network.gateway
  athena_vlan_id     = local.athena_network.vlan_id
  athena_subnet      = local.athena_network.subnet
  athena_subnet_cidr = split("/", local.athena_subnet)[1]

  windows_server_ip     = cidrhost(local.athena_subnet, 50)
  github_runner_ip      = cidrhost(local.athena_subnet, 70)
  talos_controlplane_ip = cidrhost(local.athena_subnet, 60)
  talos_worker_ips = [
    cidrhost(local.athena_subnet, 61),
    cidrhost(local.athena_subnet, 62),
    cidrhost(local.athena_subnet, 63),
    cidrhost(local.athena_subnet, 64),
    cidrhost(local.athena_subnet, 65),
  ]

}
