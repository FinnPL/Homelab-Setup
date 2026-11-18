# Unbound's DoT to Cloudflare leaves through Proton.
resource "unifi_vpn_client" "proton_dns" {
  name   = "DNS"
  subnet = "10.2.0.10/32"

  wireguard = {
    private_key_wo         = var.protonvpn_private_key
    private_key_wo_version = 1
    dns_servers            = ["10.2.0.1"]

    peer = {
      ip         = "149.88.102.97"
      port       = 51820
      public_key = "hOoBBy//7mddXPz1SybzWB3zK95SQCcPyI/DmxfULXk="
    }
  }
}

resource "unifi_traffic_route" "proton_dot" {
  description         = "DNS"
  network_id          = unifi_vpn_client.proton_dns.id
  kill_switch_enabled = false

  destination = {
    ip = [
      { address = "1.1.1.1", ports = ["853"] },
      { address = "1.0.0.1", ports = ["853"] },
    ]
  }
}
