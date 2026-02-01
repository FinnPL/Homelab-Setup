locals {
  athena_subnet  = "10.10.1.0/24"
  lb_start_index = 200 # end of dhcp -> cilium LB start
}
resource "unifi_network" "tf_vlan_athena" {
  name    = "tf-Athena"
  purpose = "corporate"

  vlan_id = 20

  subnet       = local.athena_subnet
  dhcp_start   = cidrhost(local.athena_subnet, 20)
  dhcp_stop    = cidrhost(local.athena_subnet, local.lb_start_index - 1)
  dhcp_enabled = true

  site = "default"

  network_isolation_enabled = true

  igmp_snooping = true
}

resource "unifi_network" "tf_vlan_default" {
  name    = "tf-Default"
  purpose = "corporate"

  vlan_id = 10

  subnet       = "10.10.10.1/24"
  dhcp_start   = "10.10.10.20"
  dhcp_stop    = "10.10.10.254"
  dhcp_enabled = true

  site = "default"


  network_isolation_enabled = true

  igmp_snooping = true
  multicast_dns = true
}
