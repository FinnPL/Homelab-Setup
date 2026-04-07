data "cloudflare_zone" "main" {
  filter = {
    name = "lippok.dev"
  }
}

# Cloud-hosted services (TLS terminated on cloud K3s)
resource "cloudflare_dns_record" "wildcard_cloud" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.cloud"
  content = oci_core_instance.edge.public_ip
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - Cloud edge node"
}

resource "cloudflare_dns_record" "cloud_root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "cloud"
  content = oci_core_instance.edge.public_ip
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - Cloud edge node"
}

# Relay services (TLSRoute to local, TLS terminated locally)
resource "cloudflare_dns_record" "wildcard_relay" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.relay"
  content = oci_core_instance.edge.public_ip
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - Cloud edge relay (TLS passthrough to local)"
}

resource "cloudflare_dns_record" "relay_root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "relay"
  content = oci_core_instance.edge.public_ip
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - Cloud edge relay (TLS passthrough to local)"
}
