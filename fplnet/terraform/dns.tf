# Forward-confirmed rDNS: every name gets an AAAA, and a PTR when its address is in our /44.
locals {
  hosts = {
    "er1.dus1"             = "2a0c:b641:f90::1"
    "wg-r64-fra4.er1.dus1" = "2a11:6c7:f00:2b4::2"
  }

  reverse_zone = "9.f.0.1.4.6.b.c.0.a.2.ip6.arpa"

  # Expand "::" to the full 32 nibbles, reversed and dotted as in ip6.arpa.
  ptr_names = {
    for name, addr in local.hosts : name => "${join(".", reverse(split("", join("", [
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
  for_each = local.hosts

  zone_id = data.cloudflare_zone.forward.id
  name    = "${each.key}.fplnet.net"
  type    = "AAAA"
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
  content = "${each.key}.fplnet.net"
}
