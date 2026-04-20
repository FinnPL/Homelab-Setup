output "instance_public_ip" {
  description = "Public IP address of the Oracle edge node"
  value       = oci_core_instance.edge.public_ip
}

output "instance_private_ip" {
  description = "Private (VCN) IP address of the Oracle edge node"
  value       = oci_core_instance.edge.private_ip
}

output "instance_id" {
  description = "OCID of the Oracle edge node compute instance"
  value       = oci_core_instance.edge.id
}

output "vcn_id" {
  description = "OCID of the edge VCN"
  value       = oci_core_vcn.edge.id
}

output "subnet_id" {
  description = "OCID of the edge public subnet"
  value       = oci_core_subnet.public.id
}

output "public_subnet_cidr" {
  description = "CIDR block of the public subnet (used by Tailscale route advertisement)"
  value       = var.public_subnet_cidr
}

output "oci_compartment_ocid" {
  description = "OCID of the compartment holding edge resources (consumed by CCM config)"
  value       = local.oci_compartment_ocid
}

output "oci_region" {
  description = "OCI region (consumed by CCM config)"
  value       = local.oci_region
}

output "gateway_lb_reserved_ip_ocid" {
  description = "OCID of the reserved public IP for the gateway load balancer"
  value       = oci_core_public_ip.gateway_lb.id
}

output "gateway_lb_reserved_ip" {
  description = "Reserved public IPv4 address for the gateway load balancer"
  value       = oci_core_public_ip.gateway_lb.ip_address
}

output "cloud_subdomain" {
  description = "Cloud-hosted services subdomain"
  value       = "*.cloud.lippok.dev"
}

output "relay_subdomain" {
  description = "Relay/passthrough services subdomain"
  value       = "*.relay.lippok.dev"
}
