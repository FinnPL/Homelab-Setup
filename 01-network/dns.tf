data "cloudflare_zone" "main" {
  name = "lippok.dev"
}

# Test entry
resource "cloudflare_record" "tf_proxmox_entry" {
  zone_id = data.cloudflare_zone.main.id
  name    = "lippok.dev"
  content = "10.10.1.41"
  type    = "A"
  proxied = false
  comment = "Managed by Terraform"
  ttl     = 60
}
