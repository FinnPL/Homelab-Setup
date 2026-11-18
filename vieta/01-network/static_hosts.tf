# One DHCP reservation and local DNS name per inventory host.
resource "unifi_client" "host" {
  for_each = local.vieta.hosts

  mac              = each.value.mac
  name             = trimsuffix(each.value.dns, ".athena")
  fixed_ip         = each.value.ipv4
  local_dns_record = each.value.dns
  note             = "Managed by Terraform"
}
