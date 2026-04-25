data "cloudflare_zone" "main" {
  filter = {
    name = var.cloudflare_zone_name
  }
}

# Relay endpoints: subdomains under relay.lippok.dev resolve to the OCI edge,
# where HAProxy SNI-routes them over wg0 to the right homelab backend.
# proxied=false: TLS terminates in the basement (Blocky), not at Cloudflare.
resource "cloudflare_dns_record" "relay_wildcard" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.relay"
  type    = "A"
  ttl     = 300
  content = oci_core_instance.edge.public_ip
  proxied = false
}
