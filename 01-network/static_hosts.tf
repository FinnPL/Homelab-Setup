resource "unifi_user" "tf_apollo_host" {
  mac              = "00:11:32:7f:65:e3"
  name             = "tf-Apollo-NAS"
  fixed_ip         = "10.10.1.195"
  local_dns_record = "apollo.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}

resource "unifi_user" "tf_pi4_host" {
  mac              = "dc:a6:32:1f:b3:fb"
  name             = "tf-Pi4"
  fixed_ip         = "10.0.10.41"
  local_dns_record = "pi4.athena"
  network_id       = unifi_network.tf_vlan_athena.id
  note             = "Managed by Terraform"
}
