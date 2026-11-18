resource "unifi_port_profile" "athena" {
  name                  = "Athena (Terraform)"
  forward               = "native"
  tagged_vlan_mgmt      = "block_all"
  poe_mode              = "off"
  native_networkconf_id = unifi_network.athena.id
}

resource "unifi_port_profile" "athena_poe" {
  name                  = "Athena (Terraform) - PoE"
  forward               = "native"
  tagged_vlan_mgmt      = "block_all"
  poe_mode              = "auto"
  native_networkconf_id = unifi_network.athena.id
}

resource "unifi_port_profile" "default" {
  name                  = "Default (Terraform)"
  forward               = "native"
  tagged_vlan_mgmt      = "block_all"
  poe_mode              = "off"
  native_networkconf_id = unifi_network.default.id
}

resource "unifi_device" "gateway" {
  name = "Vieta"
  mac  = "28:70:4e:3e:fb:15"

  lifecycle {
    prevent_destroy = true
  }

  port_override {
    index           = 1
    name            = "tf-Port1"
    port_profile_id = unifi_port_profile.default.id
  }
  port_override {
    index           = 2
    name            = "tf-Port2"
    port_profile_id = unifi_port_profile.athena.id
  }
  port_override {
    index           = 3
    name            = "tf-Port3"
    port_profile_id = unifi_port_profile.athena.id
  }
  # Port 4 keeps the default (all VLANs).
}

resource "unifi_device" "switch" {
  name = "USW-Ultra"
  mac  = "58:d6:1f:5e:85:8e"

  lifecycle {
    prevent_destroy = true
  }

  # Pis and the DietPi, powered over PoE.
  dynamic "port_override" {
    for_each = [1, 2, 3, 5]
    content {
      index           = port_override.value
      name            = "tf-Port${port_override.value}"
      port_profile_id = unifi_port_profile.athena_poe.id
    }
  }

  port_override {
    index           = 4
    name            = "tf-Port4"
    port_profile_id = unifi_port_profile.athena.id
  }
}

resource "unifi_device" "flex_25g" {
  name = "USW Flex 2.5G 8 PoE"
  mac  = "8c:ed:e1:72:5b:1f"

  lifecycle {
    prevent_destroy = true
  }

  port_override {
    index           = 4
    name            = "tf-Port4"
    port_profile_id = unifi_port_profile.athena_poe.id
  }
}

resource "unifi_device" "flex_mini" {
  name = "Switch Flex Mini"
  mac  = "28:70:4e:32:53:14"

  lifecycle {
    prevent_destroy = true
  }

  port_override {
    index           = 2
    name            = "tf-Port2"
    port_profile_id = unifi_port_profile.default.id
  }

  dynamic "port_override" {
    for_each = [3, 4, 5]
    content {
      index           = port_override.value
      name            = "tf-Port${port_override.value}"
      port_profile_id = unifi_port_profile.athena.id
    }
  }
}
