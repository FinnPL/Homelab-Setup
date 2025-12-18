data "unifi_port_profile" "disabled" {
  name = "Disabled"
}

data "unifi_port_profile" "all" {
  name = "All"
}

resource "unifi_device" "tf_cgu" {
  name = "tf-Cloud-Gateway-Ultra"
  mac  = "28:70:4e:3e:fb:15"

  port_override {
    number          = 2
    name            = "tf-Port2"
    port_profile_id = unifi_network.tf_vlan_athena.id
  }
}
