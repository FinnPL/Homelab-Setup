output "tf_debug_unifi_site" {
  description = "UniFi site targeted by this module"
  value       = "default"
}

output "tf_debug_network_ids" {
  description = "Network IDs from Terraform state (useful for drift/debug)"
  value = {
    athena  = unifi_network.tf_vlan_athena.id
    default = unifi_network.tf_vlan_default.id
  }
}

output "tf_debug_networks" {
  description = "Debug details of managed networks (name/vlan/subnet)"
  value = {
    athena = {
      name   = unifi_network.tf_vlan_athena.name
      vlan   = unifi_network.tf_vlan_athena.vlan_id
      subnet = unifi_network.tf_vlan_athena.subnet
    }
    default = {
      name   = unifi_network.tf_vlan_default.name
      vlan   = unifi_network.tf_vlan_default.vlan_id
      subnet = unifi_network.tf_vlan_default.subnet
    }
  }
}

output "tf_debug_firewall_intent" {
  description = "Firewall intent (disabled for now due to UniFi rule_index mismatch)"
  value = {
    ruleset = "LAN_IN"
    rules = [
      {
        name      = "tf-allow-athena-to-default-https-ssh-smb"
        action    = "accept"
        protocol  = "tcp_udp"
        dst_ports = "443,22,445"
        src       = "tf-Athena"
        dst       = "tf-Default"
      },
      {
        name      = "tf-allow-default-to-athena-https-ssh-smb"
        action    = "accept"
        protocol  = "tcp_udp"
        dst_ports = "443,22,445"
        src       = "tf-Default"
        dst       = "tf-Athena"
      },
      {
        name     = "tf-allow-athena-to-athenalink-gateway-10.0.3.2"
        action   = "accept"
        protocol = "all"
        dst_ip   = "10.0.3.2/32"
        src      = "tf-Athena"
      },
      {
        name     = "tf-block-athenalink-gateway-10.0.3.2"
        action   = "drop"
        protocol = "all"
        dst_ip   = "10.0.3.2/32"
        src      = "any"
      },
    ]
  }
}
