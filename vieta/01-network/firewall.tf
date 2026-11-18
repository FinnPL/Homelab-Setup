# Zone-based firewall:
# - Default -> Athena only HTTPS (443), SMB (445), SSH (22)
# - no other network reaches Athena (network isolation)
# - Default -> Blocky (Athena LB) for DNS
# - Default -> JetKVM, all ports (HTTP UI and WebRTC video on UDP)
# - only Athena reaches the AthenaLink VPN gateway (10.0.3.2)

data "unifi_firewall_zone" "internal" {
  name = "Internal"
}

data "unifi_firewall_zone" "external" {
  name = "External"
}

resource "unifi_firewall_zone" "athena_lan" {
  name        = "tf-Athena"
  network_ids = [unifi_network.athena.id]
}

resource "unifi_firewall_group" "athena_services" {
  name    = "tf-athena-default-services"
  type    = "port-group"
  members = ["22", "443", "445"]
}

resource "unifi_firewall_policy" "internal_to_athena" {
  name                 = "tf-allow-internal-to-athena-services"
  action               = "ALLOW"
  protocol             = "tcp_udp"
  create_allow_respond = true

  source = {
    zone_id         = data.unifi_firewall_zone.internal.id
    matching_target = "ANY"
  }

  destination = {
    zone_id            = unifi_firewall_zone.athena_lan.id
    matching_target    = "ANY"
    port_matching_type = "OBJECT"
    port_group_id      = unifi_firewall_group.athena_services.id
  }
}

resource "unifi_firewall_policy" "internal_to_blocky" {
  name                 = "tf-allow-internal-to-blocky"
  action               = "ALLOW"
  protocol             = "tcp_udp"
  create_allow_respond = true

  source = {
    zone_id         = data.unifi_firewall_zone.internal.id
    matching_target = "ANY"
  }

  destination = {
    zone_id            = unifi_firewall_zone.athena_lan.id
    matching_target    = "IP"
    ips                = [local.blocky]
    port_matching_type = "SPECIFIC"
    port               = "53"
  }
}

resource "unifi_firewall_policy" "internal_to_kvm" {
  name                 = "tf-allow-internal-to-kvm"
  action               = "ALLOW"
  protocol             = "all"
  create_allow_respond = true

  source = {
    zone_id         = data.unifi_firewall_zone.internal.id
    matching_target = "ANY"
  }

  destination = {
    zone_id         = unifi_firewall_zone.athena_lan.id
    matching_target = "IP"
    ips             = [local.vieta.hosts.kvm.ipv4]
  }
}

resource "unifi_firewall_policy" "athena_to_athenalink" {
  name     = "tf-allow-athena-to-external"
  action   = "ALLOW"
  protocol = "all"

  source = {
    zone_id         = unifi_firewall_zone.athena_lan.id
    matching_target = "ANY"
  }

  destination = {
    zone_id         = data.unifi_firewall_zone.external.id
    matching_target = "IP"
    ips             = ["10.0.3.2"]
  }
}

resource "unifi_firewall_policy" "block_internal_to_athenalink" {
  name     = "tf-block-internal-to-athenalink"
  action   = "BLOCK"
  protocol = "all"

  source = {
    zone_id         = data.unifi_firewall_zone.internal.id
    matching_target = "ANY"
  }

  destination = {
    zone_id         = data.unifi_firewall_zone.external.id
    matching_target = "IP"
    ips             = ["10.0.3.2"]
  }
}
