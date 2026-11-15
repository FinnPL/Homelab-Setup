data "terraform_remote_state" "vault" {
  backend = "s3"

  config = {
    bucket = "finnpl-homelab-tfstate-1766068376"
    key    = "vault/terraform.tfstate"
    region = "eu-central-1"
  }
}

locals {
  vieta = jsondecode(file("${path.module}/../../inventory/vieta.json")).inventory.vieta
  hosts = local.vieta.hosts

  vault_user_ca_authorized_key = format(
    "cert-authority,principals=\"root\" %s",
    trimspace(file("${path.module}/../../inventory/trust/vault_user_ca.pub"))
  )

  proxmox_host_ip = local.hosts.nuc.ipv4
  athena_gateway  = local.vieta.lan.gateway
  athena_vlan_id  = local.vieta.lan.vlan
  athena_subnet   = local.vieta.lan.network

  windows_server_ip     = local.hosts.win.ipv4
  talos_controlplane_ip = local.hosts.cp1.ipv4
  nfs_server_ip         = local.hosts.nfs.ipv4

  talos_worker_ips = [
    local.hosts.pi1.ipv4,
    local.hosts.pi2.ipv4,
    local.hosts.pi3.ipv4,
  ]

  talos_controlplane_mac = local.hosts.cp1.mac
  windows_server_mac     = local.hosts.win.mac
  nfs_server_mac         = local.hosts.nfs.mac
}
