output "instance_public_ip" {
  description = "Public IP address of the Oracle edge node"
  value       = oci_core_instance.edge.public_ip
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

output "cloud_subdomain" {
  description = "Cloud-hosted services subdomain"
  value       = "*.cloud.lippok.dev"
}

output "relay_subdomain" {
  description = "Relay/passthrough services subdomain"
  value       = "*.relay.lippok.dev"
}
