resource "unifi_network" "tf_vlan_athena" {
  name    = "tf-Athena"
  purpose = "corporate"

  vlan_id = 10

  subnet       = "10.0.10.1/24"
  dhcp_start   = "10.0.10.20"
  dhcp_stop    = "10.0.10.254"
  dhcp_enabled = true

  site = "default"
  
  igmp_snooping = true
}