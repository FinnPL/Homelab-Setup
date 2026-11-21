locals {
  fplnet_routers = jsondecode(file("${path.module}/../../inventory/fplnet.json")).inventory.fplnet.routers

  lan_routers = {
    for name, r in local.fplnet_routers : name => {
      ipv4 = split("/", r.uplink.v4)[0]
      mac  = r.uplink.mac
      dns  = "${name}.athena"
    } if cidrhost(r.uplink.v4, 0) == cidrhost(local.lan.network, 0)
  }
}

# One DHCP reservation and local DNS name per inventory host.
resource "unifi_client" "host" {
  for_each = merge(local.vieta.hosts, local.lan_routers)

  mac              = each.value.mac
  name             = trimsuffix(each.value.dns, ".athena")
  fixed_ip         = each.value.ipv4
  local_dns_record = each.value.dns
  note             = "Managed by Terraform"
}
