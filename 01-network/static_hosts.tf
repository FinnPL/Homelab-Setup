resource "unifi_user" "tf_apollo_host" {
  mac        = "00:11:32:7f:65:e3"
  name       = "tf-Apollo-NAS"
  fixed_ip   = "10.10.1.195"
  network_id = unifi_network.tf_vlan_athena.id
  note       = "Managed by Terraform"
}
