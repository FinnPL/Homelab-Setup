data "cloudflare_zone" "main" {
  filter = {
    name = "lippok.dev"
  }
}

# DNS records for K8s Gateway LB

resource "cloudflare_dns_record" "wildcard_homelab" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*"
  content = local.gateway_lb_ip
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - K8s Gateway LB"

  depends_on = [kubectl_manifest.main_gateway]
}

resource "cloudflare_dns_record" "root_homelab" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = local.gateway_lb_ip
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - K8s Gateway LB"

  depends_on = [kubectl_manifest.main_gateway]
}
