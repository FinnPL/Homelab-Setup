data "cloudflare_zone" "main" {
  filter = {
    name = "lippok.dev"
  }
}

resource "cloudflare_dns_record" "tf_pi4_entry" {
  zone_id = data.cloudflare_zone.main.id
  name    = "lippok.dev"
  content = unifi_user.tf_pi4_host.fixed_ip
  type    = "A"
  proxied = false
  comment = "Managed by Terraform"
  ttl     = 60
}
