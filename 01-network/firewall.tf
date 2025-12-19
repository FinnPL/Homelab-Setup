# =============================================================================
# Zone-Based Firewall Configuration
# =============================================================================
# - Only HTTPS (443), SMB (445), SSH (22) between Default -> Athena
# - No other VLAN has access to Athena (network isolation)
# - Only Athena has access to AthenaLink VPN gateway (10.0.3.2)
# =============================================================================

# Zones
data "unifi_firewall_zone" "internal" {
  name = "Internal"
  site = "default"
}

data "unifi_firewall_zone" "external" {
  name = "External"
  site = "default"
}
resource "unifi_firewall_zone" "athena" {
  name     = "tf-Athena"
  networks = [unifi_network.tf_vlan_athena.id]
  site     = "default"
}

# Port Groups
resource "unifi_firewall_group" "athena_default_services" {
  name    = "tf-athena-default-services"
  type    = "port-group"
  members = ["22", "443", "445"]
  site    = "default"
}

# Zone Policies

# Allow Internal (Default) -> Athena for HTTPS, SSH, SMB and return traffic
resource "unifi_firewall_zone_policy" "internal_to_athena" {
  name                      = "tf-allow-internal-to-athena-services"
  action                    = "ALLOW"
  protocol                  = "tcp_udp"
  auto_allow_return_traffic = true

  source = {
    zone_id = data.unifi_firewall_zone.internal.id
  }

  destination = {
    zone_id       = unifi_firewall_zone.athena.id
    port_group_id = unifi_firewall_group.athena_default_services.id
  }

  site = "default"
}

# Allow Athena -> External (for AthenaLink VPN access)
resource "unifi_firewall_zone_policy" "athena_to_external" {
  name                      = "tf-allow-athena-to-external"
  action                    = "ALLOW"
  protocol                  = "all"
  auto_allow_return_traffic = true

  source = {
    zone_id = unifi_firewall_zone.athena.id
  }

  destination = {
    zone_id = data.unifi_firewall_zone.external.id
    ips     = ["10.0.3.2"]
  }

  site = "default"
}

# Block all other zones from reaching External/AthenaLink VPN gateway
resource "unifi_firewall_zone_policy" "block_internal_to_athenalink" {
  name     = "tf-block-internal-to-athenalink"
  action   = "BLOCK"
  protocol = "all"
  index    = 10000 # Lower priority than allow rules

  source = {
    zone_id = data.unifi_firewall_zone.internal.id
  }

  destination = {
    zone_id = data.unifi_firewall_zone.external.id
    ips     = ["10.0.3.2"]
  }

  site = "default"
}
