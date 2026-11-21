# Forward-confirmed rDNS: every name gets an AAAA, and a PTR when its address is in our /44.
locals {
  inventory = jsondecode(file("${path.module}/../../inventory/fplnet.json")).inventory.fplnet
  vieta     = jsondecode(file("${path.module}/../../inventory/vieta.json")).inventory.vieta
  routers   = local.inventory.routers
  links     = local.inventory.links

  # Interface addresses in the inventory carry their prefix length, split off here.
  hosts = {
    "er1.ams1"             = local.routers["er1-ams1"].loopback
    "er1.dus1"             = local.routers["er1-dus1"].loopback
    "er1.fra1"             = local.routers["er1-fra1"].loopback
    "gw1.aah1"             = local.routers["gw1-aah1"].loopback
    "eth0.gw1.aah1"        = split("/", local.routers["gw1-aah1"].uplink.v6)[0]
    "ens18.er1.ams1"       = split("/", local.routers["er1-ams1"].uplink.v6)[0]
    "interix.er1.ams1"     = split("/", local.routers["er1-ams1"].interfaces.interix.v6)[0]
    "ens18.er1.dus1"       = split("/", local.routers["er1-dus1"].uplink.v6)[0]
    "enp1s0.er1.fra1"      = split("/", local.routers["er1-fra1"].uplink.v6)[0]
    "wg-er1-ams1.er1.dus1" = local.links["er1-dus1/er1-ams1"].addresses["er1-dus1"]
    "wg-er1-dus1.er1.ams1" = local.links["er1-dus1/er1-ams1"].addresses["er1-ams1"]
    "wg-gw1-aah1.er1.dus1" = local.links["er1-dus1/gw1-aah1"].addresses["er1-dus1"]
    "wg-er1-dus1.gw1.aah1" = local.links["er1-dus1/gw1-aah1"].addresses["gw1-aah1"]
    "wg-gw1-aah1.er1.ams1" = local.links["er1-ams1/gw1-aah1"].addresses["er1-ams1"]
    "wg-er1-ams1.gw1.aah1" = local.links["er1-ams1/gw1-aah1"].addresses["gw1-aah1"]
    "wg-er1-fra1.er1.dus1" = local.links["er1-dus1/er1-fra1"].addresses["er1-dus1"]
    "wg-er1-dus1.er1.fra1" = local.links["er1-dus1/er1-fra1"].addresses["er1-fra1"]
    "wg-er1-fra1.er1.ams1" = local.links["er1-ams1/er1-fra1"].addresses["er1-ams1"]
    "wg-er1-ams1.er1.fra1" = local.links["er1-ams1/er1-fra1"].addresses["er1-fra1"]
    "wg-gw1-aah1.er1.fra1" = local.links["er1-fra1/gw1-aah1"].addresses["er1-fra1"]
    "wg-er1-fra1.gw1.aah1" = local.links["er1-fra1/gw1-aah1"].addresses["gw1-aah1"]
    "wg-r64-fra4.er1.dus1" = split("/", local.routers["er1-dus1"].interfaces["wg-r64-fra4"].v6)[0]
  }

  # Talos nodes by role, at f94:20::<last v4 octet>; gw1-aah1's BGP sessions read the same list.
  k8s_nodes = {
    for name, h in local.vieta.hosts :
    "${name}.k8s.aah1" => "${trimsuffix(local.vieta.nodeNetwork, "/64")}${split(".", h.ipv4)[3]}" if can(h.k8sNode)
  }

  names = merge(local.hosts, local.k8s_nodes)

  # The PTR of these lives with the provider, set in its panel.
  hosts_v4 = {
    "ens18.er1.ams1"   = split("/", local.routers["er1-ams1"].uplink.v4)[0]
    "interix.er1.ams1" = split("/", local.routers["er1-ams1"].interfaces.interix.v4)[0]
    "ens18.er1.dus1"   = split("/", local.routers["er1-dus1"].uplink.v4)[0]
    "enp1s0.er1.fra1"  = split("/", local.routers["er1-fra1"].uplink.v4)[0]
  }

  # Site services keep their lippok.dev names and 03-services writes the matching AAAA.
  site_services = { for name, s in local.inventory.siteServices : name => s.address }

  ptr_targets = merge(
    { for name in keys(local.names) : name => "${name}.fplnet.net" },
    { "@" = "fplnet.net" },
    { for name in keys(local.site_services) : name => name },
  )

  reverse_zone = "9.f.0.1.4.6.b.c.0.a.2.ip6.arpa"

  # Expand "::" to the full 32 nibbles, reversed and dotted as in ip6.arpa.
  # "@" is the apex, fplnet.net itself.
  ptr_names = {
    for name, addr in merge(local.names, { "@" = local.web_v6 }, local.site_services) : name => "${join(".", reverse(split("", join("", [
      for g in concat(
        compact(split(":", split("::", addr)[0])),
        [for _ in range(8 - length(compact(split(":", addr)))) : "0"],
        compact(split(":", try(split("::", addr)[1], ""))),
      ) : substr("000${g}", length(g) - 1, 4)
    ]))))}.ip6.arpa"
  }
}

data "cloudflare_zone" "forward" {
  filter = {
    name = "fplnet.net"
  }
}

data "cloudflare_zone" "reverse" {
  filter = {
    name = local.reverse_zone
  }
}

resource "cloudflare_dns_record" "aaaa" {
  for_each = local.names

  zone_id = data.cloudflare_zone.forward.id
  name    = "${each.key}.fplnet.net"
  type    = "AAAA"
  ttl     = 3600
  content = each.value
  proxied = false
}

resource "cloudflare_dns_record" "a" {
  for_each = local.hosts_v4

  zone_id = data.cloudflare_zone.forward.id
  name    = "${each.key}.fplnet.net"
  type    = "A"
  ttl     = 3600
  content = each.value
  proxied = false
}

resource "cloudflare_dns_record" "ptr" {
  for_each = {
    for name, ptr in local.ptr_names : name => ptr
    if endswith(ptr, ".${local.reverse_zone}")
  }

  zone_id = data.cloudflare_zone.reverse.id
  name    = each.value
  type    = "PTR"
  ttl     = 3600
  content = local.ptr_targets[each.key]
}

# fplnet.net: the edge anycast address over IPv6, every edge's provider address over IPv4 (no own v4).
locals {
  web_v6 = local.inventory.edgeAnycastAddress

  # Each edge's uplink in hosts_v4
  edge_uplinks = {
    "er1.ams1" = "ens18.er1.ams1"
    "er1.dus1" = "ens18.er1.dus1"
    "er1.fra1" = "enp1s0.er1.fra1"
  }
  web_v4 = { for edge, uplink in local.edge_uplinks : uplink => local.hosts_v4[uplink] }
}

resource "cloudflare_dns_record" "web_aaaa" {
  zone_id = data.cloudflare_zone.forward.id
  name    = "fplnet.net"
  type    = "AAAA"
  ttl     = 300
  content = local.web_v6
  proxied = false
}

resource "cloudflare_dns_record" "web_a" {
  for_each = local.web_v4

  zone_id = data.cloudflare_zone.forward.id
  name    = "fplnet.net"
  type    = "A"
  ttl     = 300
  content = each.value
  proxied = false
}

# fplnet.net/connection tests each address family on a name that has only that family.
resource "cloudflare_dns_record" "web_v4_only" {
  for_each = local.web_v4

  zone_id = data.cloudflare_zone.forward.id
  name    = "v4.fplnet.net"
  type    = "A"
  ttl     = 300
  content = each.value
  proxied = false
}

resource "cloudflare_dns_record" "web_v6_only" {
  zone_id = data.cloudflare_zone.forward.id
  name    = "v6.fplnet.net"
  type    = "AAAA"
  ttl     = 300
  content = local.web_v6
  proxied = false
}

resource "cloudflare_dns_record" "edge_a" {
  for_each = local.edge_uplinks

  zone_id = data.cloudflare_zone.forward.id
  name    = "${each.key}.fplnet.net"
  type    = "A"
  ttl     = 3600
  content = local.hosts_v4[each.value]
  proxied = false
}

# Advertises HTTP/3 and the ECH public key.
resource "cloudflare_dns_record" "web_https" {
  zone_id = data.cloudflare_zone.forward.id
  name    = "fplnet.net"
  type    = "HTTPS"
  ttl     = 300
  data = {
    priority = 1
    target   = "."
    value    = "alpn=\"h3,h2\" ech=\"${trimspace(file("${path.module}/fplnet-net.echconfig"))}\""
  }
}

# lg.fplnet.net
resource "cloudflare_dns_record" "lg_aaaa" {
  zone_id = data.cloudflare_zone.forward.id
  name    = "lg.fplnet.net"
  type    = "AAAA"
  ttl     = 300
  content = local.web_v6
  proxied = false
}

resource "cloudflare_dns_record" "lg_a" {
  for_each = local.web_v4

  zone_id = data.cloudflare_zone.forward.id
  name    = "lg.fplnet.net"
  type    = "A"
  ttl     = 300
  content = each.value
  proxied = false
}

resource "cloudflare_dns_record" "lg_https" {
  zone_id = data.cloudflare_zone.forward.id
  name    = "lg.fplnet.net"
  type    = "HTTPS"
  ttl     = 300
  data = {
    priority = 1
    target   = "."
    value    = "alpn=\"h3,h2\" ech=\"${trimspace(file("${path.module}/fplnet-net.echconfig"))}\""
  }
}

# Only Let's Encrypt may issue, and only through DNS-01
resource "cloudflare_dns_record" "caa" {
  for_each = {
    issue     = "letsencrypt.org; validationmethods=dns-01"
    issuewild = ";"
    iodef     = "mailto:noc@lippok.eu"
  }

  zone_id = data.cloudflare_zone.forward.id
  name    = "fplnet.net"
  type    = "CAA"
  ttl     = 3600
  data = {
    flags = 0
    tag   = each.key
    value = each.value
  }
}
