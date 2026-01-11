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
    apollo             = unifi_user.tf_apollo_host.fixed_ip
    pi4                = unifi_user.tf_pi4_host.fixed_ip
    nuc                = unifi_user.tf_nuc_host.fixed_ip
    windows_server     = unifi_user.tf_windows_server.fixed_ip
    talos_controlplane = unifi_user.tf_talos_controlplane.fixed_ip
    github_runner      = unifi_user.tf_github_runner.fixed_ip
  }
}

output "host_macs" {
  description = "Static host MAC addresses"
  value       = var.host_macs
}
