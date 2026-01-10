output "athena_network" {
  description = "Athena VLAN network configuration"
  value = {
    id      = unifi_network.tf_vlan_athena.id
    name    = unifi_network.tf_vlan_athena.name
    vlan_id = unifi_network.tf_vlan_athena.vlan_id
    subnet  = unifi_network.tf_vlan_athena.subnet
    gateway = cidrhost(unifi_network.tf_vlan_athena.subnet, 1)
  }
}

output "host_ips" {
  description = "Static host IP addresses"
  value = {
    apollo = unifi_user.tf_apollo_host.fixed_ip
    pi4    = unifi_user.tf_pi4_host.fixed_ip
    nuc    = unifi_user.tf_nuc_host.fixed_ip
  }
}
