# Names served in the cluster and reached through the FPLNET edges (fplnet/nixos/site-services.json):
# AAAA = the Service's public address, routed natively via the edges and gw1-aah1;
# A = every edge, whose HAProxy passes the TLS stream by SNI over the backbone.
locals {
  site_services = jsondecode(file("${path.module}/../fplnet/nixos/site-services.json"))

  edge_v4 = [for name, h in jsondecode(file("${path.module}/../fplnet/hosts.json")) : h.ssh if startswith(name, "er1-")]

  site_service_a = {
    for pair in setproduct(keys(local.site_services), local.edge_v4) : "${pair[0]} ${pair[1]}" => {
      name = pair[0]
      ip   = pair[1]
    }
  }
}

resource "cloudflare_dns_record" "site_service_aaaa" {
  for_each = local.site_services

  zone_id = data.cloudflare_zone.main.id
  name    = each.key
  type    = "AAAA"
  ttl     = 300
  content = each.value.address
  proxied = false
  comment = "Managed by Terraform - site service via FPLNET"

  lifecycle {
    precondition {
      condition     = endswith(each.key, ".lippok.dev")
      error_message = "03-services only manages lippok.dev."
    }
  }
}

resource "cloudflare_dns_record" "site_service_a" {
  for_each = local.site_service_a

  zone_id = data.cloudflare_zone.main.id
  name    = each.value.name
  type    = "A"
  ttl     = 300
  content = each.value.ip
  proxied = false
  comment = "Managed by Terraform - FPLNET edge relay"

  lifecycle {
    precondition {
      condition     = endswith(each.value.name, ".lippok.dev")
      error_message = "03-services only manages lippok.dev."
    }
  }
}
