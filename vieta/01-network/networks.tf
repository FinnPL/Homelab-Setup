locals {
  vieta = jsondecode(file("${path.module}/../../inventory/vieta.json")).inventory.vieta
  lan   = local.vieta.lan

  # DHCP hands out .20 up to the address before the Cilium LB range.
  lb_first_host = tonumber(split(".", cidrhost(local.lan.loadBalancers, 0))[3])
  blocky        = local.lan.loadBalancerIPs.dns
  ntp1          = local.vieta.hosts.ntp1.ipv4
}

resource "unifi_network" "athena" {
  name    = "tf-Athena"
  purpose = "corporate"
  vlan    = local.lan.vlan
  subnet  = "${local.lan.gateway}/${split("/", local.lan.network)[1]}"

  dhcp_server = {
    enabled = true
    start   = cidrhost(local.lan.network, 20)
    stop    = cidrhost(local.lan.network, local.lb_first_host - 1)
    ntp = {
      enabled = true
      servers = [local.ntp1]
    }
  }

  network_isolation = true
}

resource "unifi_network" "default" {
  name    = "tf-Default"
  purpose = "corporate"
  vlan    = 10
  subnet  = "10.10.10.1/24"

  dhcp_server = {
    enabled = true
    start   = "10.10.10.20"
    stop    = "10.10.10.254"
    dns = {
      enabled = true
      servers = [local.blocky]
    }
    ntp = {
      enabled = true
      servers = [local.ntp1]
    }
  }

  network_isolation = true
  multicast_dns     = true
}

data "unifi_network" "management" {
  name = "Default"
}
