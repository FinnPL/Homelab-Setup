# Forward-confirmed rDNS: every name gets an AAAA, and a PTR when its address is in our /44.
locals {
  hosts = {
    "er1.ams1"             = "2a0c:b641:f99::1"
    "er1.dus1"             = "2a0c:b641:f98::1"
    "er1.fra1"             = "2a0c:b641:f9a::1"
    "gw1.aah1"             = "2a0c:b641:f94::1"
    "eth0.gw1.aah1"        = "2a0c:b641:f94:20::1"
    "ens18.er1.ams1"       = "2602:fa7e:17::3f"
    "interix.er1.ams1"     = "2001:7f8:134::10e"
    "ens18.er1.dus1"       = "2a0c:b640:11:178::1"
    "enp1s0.er1.fra1"      = "2a05:f480:1800:28:5400:7ff:fe06:3983"
    "wg-er1-ams1.er1.dus1" = "2a0c:b641:f98:1001::"
    "wg-er1-dus1.er1.ams1" = "2a0c:b641:f98:1001::1"
    "wg-gw1-aah1.er1.dus1" = "2a0c:b641:f98:1000::"
    "wg-er1-dus1.gw1.aah1" = "2a0c:b641:f98:1000::1"
    "wg-gw1-aah1.er1.ams1" = "2a0c:b641:f99:1000::"
    "wg-er1-ams1.gw1.aah1" = "2a0c:b641:f99:1000::1"
    "wg-er1-fra1.er1.dus1" = "2a0c:b641:f98:1002::"
    "wg-er1-dus1.er1.fra1" = "2a0c:b641:f98:1002::1"
    "wg-er1-fra1.er1.ams1" = "2a0c:b641:f99:1001::"
    "wg-er1-ams1.er1.fra1" = "2a0c:b641:f99:1001::1"
    "wg-gw1-aah1.er1.fra1" = "2a0c:b641:f9a:1000::"
    "wg-er1-fra1.gw1.aah1" = "2a0c:b641:f9a:1000::1"
    "wg-r64-fra4.er1.dus1" = "2a11:6c7:f00:2b4::2"
  }

  # Talos nodes by role, at f94:20::<last v4 octet>; gw1-aah1's BGP sessions read the same file.
  k8s_nodes = {
    for octet, n in jsondecode(file("${path.module}/../nixos/k8s-nodes.json")) :
    "${n.name}.k8s.aah1" => "2a0c:b641:f94:20::${octet}"
  }

  names = merge(local.hosts, local.k8s_nodes)

  # The PTR of these lives with the provider, set in its panel.
  hosts_v4 = {
    "ens18.er1.ams1"   = "188.65.164.27"
    "interix.er1.ams1" = "185.1.185.17"
    "ens18.er1.dus1"   = "194.28.99.178"
    "enp1s0.er1.fra1"  = "209.250.233.8"
  }

  reverse_zone = "9.f.0.1.4.6.b.c.0.a.2.ip6.arpa"

  # Expand "::" to the full 32 nibbles, reversed and dotted as in ip6.arpa.
  # "@" is the apex, fplnet.net itself.
  ptr_names = {
    for name, addr in merge(local.names, { "@" = local.web_v6 }) : name => "${join(".", reverse(split("", join("", [
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
  content = each.key == "@" ? "fplnet.net" : "${each.key}.fplnet.net"
}

# fplnet.net: the edge anycast address over IPv6, every edge's provider address over IPv4 (no own v4).
locals {
  web_v6 = "2a0c:b641:f91::80"
  web_v4 = {
    for name in ["ens18.er1.ams1", "ens18.er1.dus1", "enp1s0.er1.fra1"] : name => local.hosts_v4[name]
  }
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
