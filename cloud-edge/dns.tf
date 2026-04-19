data "cloudflare_zone" "main" {
  filter = {
    name = "lippok.dev"
  }
}

# Reserved public IP for the OCI Load Balancer (Cilium gateway)
resource "oci_core_public_ip" "gateway_lb" {
  compartment_id = local.oci_compartment_ocid
  display_name   = "cilium-gateway-lb"
  lifetime       = "RESERVED"
}

# Cloud-hosted services (TLS terminated on cloud K3s)
resource "cloudflare_dns_record" "wildcard_cloud" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.cloud"
  content = oci_core_public_ip.gateway_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - OCI LB (Cilium gateway)"
}

resource "cloudflare_dns_record" "cloud_root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "cloud"
  content = oci_core_public_ip.gateway_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - OCI LB (Cilium gateway)"
}

# Relay services (TLSRoute to local, TLS terminated locally)
resource "cloudflare_dns_record" "wildcard_relay" {
  zone_id = data.cloudflare_zone.main.id
  name    = "*.relay"
  content = oci_core_public_ip.gateway_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - OCI LB (Cilium gateway)"
}

resource "cloudflare_dns_record" "relay_root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "relay"
  content = oci_core_public_ip.gateway_lb.ip_address
  type    = "A"
  proxied = false
  ttl     = 60
  comment = "Managed by Terraform - OCI LB (Cilium gateway)"
}
