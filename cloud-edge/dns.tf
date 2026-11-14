data "cloudflare_zone" "main" {
  filter = {
    name = var.cloudflare_zone_name
  }
}

resource "cloudflare_dns_record" "apex_homepage" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "AAAA"
  ttl     = 1
  content = "2a0c:b641:f91::80"
  proxied = true

  lifecycle {
    create_before_destroy = true
  }
}
