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

output "athena_lb_cidr" {
  description = "Cilium LoadBalancer CIDR block"
  value       = "${cidrhost(local.athena_subnet, local.lb_start_index)}/29"
}

output "host_ips" {
  description = "Static host IP addresses"
  value = {
    apollo             = unifi_user.tf_apollo_host.fixed_ip
    nuc                = unifi_user.tf_nuc_host.fixed_ip
    windows_server     = unifi_user.tf_windows_server.fixed_ip
    talos_controlplane = unifi_user.tf_talos_controlplane.fixed_ip
    github_runner      = unifi_user.tf_github_runner.fixed_ip
    nfs_server         = unifi_user.tf_nfs_server.fixed_ip
    talos_worker_1     = unifi_user.tf_talos_worker_1.fixed_ip
    talos_worker_2     = unifi_user.tf_talos_worker_2.fixed_ip
    talos_worker_3     = unifi_user.tf_talos_worker_3.fixed_ip
    talos_worker_4     = unifi_user.tf_talos_worker_4.fixed_ip
    talos_worker_5     = unifi_user.tf_talos_worker_5.fixed_ip
  }
}

output "host_vm_macs" {
  description = "Static VM MAC addresses"
  value       = var.host_vm_macs
}