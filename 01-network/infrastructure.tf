data "unifi_port_profile" "athena_profile" {
  name       = unifi_network.tf_vlan_athena.name
  depends_on = [unifi_network.tf_vlan_athena]
}

resource "unifi_device" "tf_cgu" {
  name = "tf-Cloud-Gateway-Ultra"
  mac  = "28:70:4e:3e:fb:15"

  port_override {
    number          = 2
    name            = "tf-Port2"
    port_profile_id = data.unifi_port_profile.athena_profile.id
  }
}
