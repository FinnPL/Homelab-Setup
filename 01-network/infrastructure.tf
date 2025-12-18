resource "unifi_port_profile" "athena_custom_profile" {
  name = "Athena (Terraform)"
  site = "default"

  forward = "customize"

  native_networkconf_id = unifi_network.tf_vlan_athena.id

  depends_on = [unifi_network.tf_vlan_athena]
}

resource "unifi_device" "tf_cgu" {
  name = "Vieta"
  mac  = "28:70:4e:3e:fb:15"
  site = "default"
  lifecycle {
    prevent_destroy = true
  }

  port_override {
    number          = 2
    name            = "tf-Port2"
    port_profile_id = unifi_port_profile.athena_custom_profile.id
  }
  port_override {
    number          = 3
    name            = "tf-Port3"
    port_profile_id = unifi_port_profile.athena_custom_profile.id
  }

}
