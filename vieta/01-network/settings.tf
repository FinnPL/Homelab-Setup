resource "unifi_setting" "site" {
  # The gateway's own resolver (used by Athena and the management LAN)
  doh = {
    state = "custom"
    custom_servers = [
      {
        server_name = "Cloudflare"
        sdns_stamp  = "sdns://AgcAAAAAAAAABzEuMS4xLjEAEmNsb3VkZmxhcmUtZG5zLmNvbQovZG5zLXF1ZXJ5"
      },
      {
        server_name = "Quad9"
        sdns_stamp  = "sdns://AgMAAAAAAAAABzkuOS45LjkADWRucy5xdWFkOS5uZXQKL2Rucy1xdWVyeQ"
      },
    ]
  }

  # Network app activity logs to Alloy's syslog VIP.
  syslog = {
    enabled          = true
    ip               = local.lan.loadBalancerIPs.syslog
    port             = 5142
    log_all_contents = true
    debug            = false
    this_controller = {
      enabled        = true
      encrypted_only = false
    }
  }
}
