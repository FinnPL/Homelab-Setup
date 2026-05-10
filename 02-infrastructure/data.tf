data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "finnpl-homelab-tfstate-1766068376"
    key    = "01-network/terraform.tfstate"
    region = "eu-central-1"
  }
}

data "terraform_remote_state" "cloud_edge" {
  backend = "s3"

  config = {
    bucket = "finnpl-homelab-tfstate-1766068376"
    key    = "cloud-edge/terraform.tfstate"
    region = "eu-central-1"
  }
}

locals {
  # Network configuration from 01-network
  athena_network = data.terraform_remote_state.network.outputs.athena_network
  host_ips       = data.terraform_remote_state.network.outputs.host_ips
  host_vm_macs   = data.terraform_remote_state.network.outputs.host_vm_macs

  # Derived values
  proxmox_host_ip    = local.host_ips.nuc
  athena_gateway     = local.athena_network.gateway
  athena_vlan_id     = local.athena_network.vlan_id
  athena_subnet      = local.athena_network.subnet
  athena_subnet_cidr = split("/", local.athena_subnet)[1]

  # IP assignments sourced from 01-network outputs (DHCP reservations)
  windows_server_ip     = local.host_ips.windows_server
  talos_controlplane_ip = local.host_ips.talos_controlplane
  nfs_server_ip         = local.host_ips.nfs_server
  postgres_server_ip    = local.host_ips.postgres_server

  talos_worker_ips = [
    local.host_ips.talos_worker_1,
    local.host_ips.talos_worker_2,
    local.host_ips.talos_worker_3,
    local.host_ips.talos_worker_4,
    local.host_ips.talos_worker_5,
    local.host_ips.talos_worker_6,
  ]

  # Mesh router
  mesh_router_ip  = local.host_ips.mesh_router
  mesh_router_mac = local.host_vm_macs.mesh_router

  # WireGuard endpoint of the cloud-edge
  mesh_wg_peer_endpoint = "${data.terraform_remote_state.cloud_edge.outputs.instance_public_ip}:51820"

  # Resolve MACs from 01-network outputs
  talos_controlplane_mac = local.host_vm_macs.talos_controlplane
  windows_server_mac     = local.host_vm_macs.windows_server
  nfs_server_mac         = local.host_vm_macs.nfs_server
}
