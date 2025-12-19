resource "unifi_network" "tf_vlan_athena" {
  name    = "tf-Athena"
  purpose = "corporate"

  vlan_id = 20

  subnet       = "10.10.1.1/24"
  dhcp_start   = "10.10.1.20"
  dhcp_stop    = "10.10.1.254"
  dhcp_enabled = true

  site = "default"

  #network_isolation_enabled = true

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
