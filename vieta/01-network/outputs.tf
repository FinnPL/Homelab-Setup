output "athena_network" {
  description = "Athena VLAN network configuration"
  value = {
    id      = unifi_network.athena.id
    name    = unifi_network.athena.name
    vlan    = unifi_network.athena.vlan
    subnet  = unifi_network.athena.subnet
    gateway = local.lan.gateway
  }
}

output "host_ips" {
  description = "Reserved host addresses"
  value       = { for k, c in unifi_client.host : k => c.fixed_ip }
}
