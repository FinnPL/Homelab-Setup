resource "unifi_port_profile" "athena_custom_profile" {
  name = "Athena (Terraform)"
  site = "default"

  forward          = "native"
  tagged_vlan_mgmt = "block_all"
  poe_mode         = "off"

  native_networkconf_id = unifi_network.tf_vlan_athena.id

  depends_on = [unifi_network.tf_vlan_athena]
}

resource "unifi_port_profile" "athena_poe_profile" {
  name = "Athena (Terraform) - PoE"
  site = "default"

  forward          = "native"
  tagged_vlan_mgmt = "block_all"
  poe_mode         = "auto"

  native_networkconf_id = unifi_network.tf_vlan_athena.id

  depends_on = [unifi_network.tf_vlan_athena]
}

resource "unifi_port_profile" "default_custom_profile" {
  name = "Default (Terraform)"
  site = "default"

  forward          = "native"
  tagged_vlan_mgmt = "block_all"
  poe_mode         = "off"

  native_networkconf_id = unifi_network.tf_vlan_default.id

  depends_on = [unifi_network.tf_vlan_default]
}

resource "unifi_device" "tf_cgu" {
  name = "Vieta"
  mac  = "28:70:4e:3e:fb:15"
  site = "default"
  lifecycle {
    prevent_destroy = true
  }

  port_override {
    number          = 1
    name            = "tf-Port1"
    port_profile_id = unifi_port_profile.default_custom_profile.id
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
  # Leave Port4 as default (Allow All VLANs)
}

resource "unifi_device" "usw_ultra" {
  name = "USW-Ultra"
  mac  = "58:d6:1f:5e:85:8e"
  site = "default"

  lifecycle {
    prevent_destroy = true
  }

  dynamic "port_override" {
    for_each = [1, 2, 3, 4, 5]
    content {
      number              = port_override.value
      name                = "tf-Port${port_override.value}"
      port_profile_id     = unifi_port_profile.athena_poe_profile.id
      aggregate_num_ports = 0
    }
  }

}
