data "cloudflare_zone" "main" {
  name = "lippok.dev"
}

# Test entry
resource "cloudflare_record" "tf_proxmox_entry" {
  zone_id = data.cloudflare_zone.main.id
  name    = "proxmox"
  value   = "10.0.10.5"
  type    = "A"
  proxied = false
  comment = "Managed by Terraform"
}