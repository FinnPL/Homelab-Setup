locals {
  athena_network_id  = unifi_network.tf_vlan_athena.id
  default_network_id = unifi_network.tf_vlan_default.id
}

resource "unifi_firewall_rule" "allow_athena_to_default_services" { #Will restrict later to only allow access to ingress IPs
  name       = "tf-allow-athena-to-default-https-ssh-smb"
  ruleset    = "LAN_IN"
  action     = "accept"
  rule_index = 2100

  protocol = "tcp_udp"
  dst_port = "443,22,445"

  src_network_id = local.athena_network_id
  dst_network_id = local.default_network_id
}

resource "unifi_firewall_rule" "allow_default_to_athena_services" {
  name       = "tf-allow-default-to-athena-https-ssh-smb"
  ruleset    = "LAN_IN"
  action     = "accept"
  rule_index = 2110

  protocol = "tcp_udp"
  dst_port = "443,22,445"

  src_network_id = local.default_network_id
  dst_network_id = local.athena_network_id
}

resource "unifi_firewall_rule" "allow_athena_to_athenalink_gateway" {
  name       = "tf-allow-athena-to-athenalink-gateway-10.0.3.2"
  ruleset    = "LAN_IN"
  action     = "accept"
  rule_index = 2200

  protocol = "all"

  src_network_id   = local.athena_network_id
  dst_network_type = "ADDRv4"
  dst_address      = "10.0.3.2/32"
}

resource "unifi_firewall_rule" "block_default_athena_link_gateway" {
  name       = "tf-block-athenalink-gateway-10.0.3.2"
  ruleset    = "LAN_IN"
  action     = "drop"
  rule_index = 2210

  protocol = "all"

  dst_network_type = "ADDRv4"
  dst_address      = "10.0.3.2/32"
}
