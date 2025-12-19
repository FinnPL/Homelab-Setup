# Temporary lookup
data "unifi_port_profile" "search_athena" {
  name = "Athena (Terraform)"
}

data "unifi_port_profile" "search_default" {
  name = "Default (Terraform)"
}

output "FOUND_ATHENA_ID" {
  value = data.unifi_port_profile.search_athena.id
}

output "FOUND_DEFAULT_ID" {
  value = data.unifi_port_profile.search_default.id
}

resource "unifi_port_profile" "athena_custom_profile" {
  name = "Athena (Terraform)"
  site = "default"

  forward = "native"

  native_networkconf_id = unifi_network.tf_vlan_athena.id

  depends_on = [unifi_network.tf_vlan_athena]
}

resource "unifi_port_profile" "default_custom_profile" {
  name = "Default (Terraform)"
  site = "default"

  forward = "native"

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

resource "unifi_device" "tf_flex_mini" {
  name = "Flex Mini"
  mac  = "28:70:4e:32:53:14"
  site = "default"
  lifecycle {
    prevent_destroy = true
  }
  # Leave Port1 as default (Allow All VLANs)
  port_override {
    number          = 2
    name            = "tf-Port2"
    port_profile_id = unifi_port_profile.default_custom_profile.id
  }
  port_override {
    number          = 3
    name            = "tf-Port3"
    port_profile_id = unifi_port_profile.athena_custom_profile.id
  }
  port_override {
    number          = 4
    name            = "tf-Port4"
    port_profile_id = unifi_port_profile.athena_custom_profile.id
  }
  port_override {
    number          = 5
    name            = "tf-Port5"
    port_profile_id = unifi_port_profile.athena_custom_profile.id
  }
}
