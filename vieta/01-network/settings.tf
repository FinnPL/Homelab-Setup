resource "unifi_setting" "site" {
  ntp = {
    setting_preference = "manual"
    ntp_server_1       = local.ntp1
    ntp_server_2       = "time.cloudflare.com"
    ntp_server_3       = "2.ubnt.pool.ntp.org"
    ntp_server_4       = "3.ubnt.pool.ntp.org"
  }

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

  usg = {
    geo_ip_filtering = {
      enabled           = true
      block             = "block"
      traffic_direction = "both"
      countries         = "CN,RU,KP"
    }
  }

  ips = {
    ips_mode         = "ips"
    memory_optimized = true
    enabled_networks = [data.unifi_network.management.id, unifi_network.athena.id, unifi_network.default.id]
    enabled_categories = [
      "botcc", "emerging-worm", "emerging-malware", "emerging-mobile", "emerging-p2p", "tor",
      "emerging-exploit", "emerging-shellcode", "emerging-dos", "emerging-attackresponse", "emerging-scan", "emerging-rpc",
      "emerging-activex", "emerging-dns", "emerging-games", "emerging-sql", "emerging-useragent", "emerging-webapps",
      "emerging-webclient", "emerging-webserver", "ciarmy", "compromised", "dshield", "emerging-ftp",
      "emerging-icmp", "emerging-imap", "emerging-misc", "emerging-netbios", "emerging-pop3", "emerging-smtp",
      "emerging-snmp", "emerging-telnet", "emerging-tftp", "emerging-voip", "dark-web-blocker-list", "malicious-hosts",
    ]
    content_filtering_blocking_page_enabled = true

    honeypot_enabled = true
    honeypot = [
      { network_id = data.unifi_network.management.id, ip_address = "10.10.0.2", version = "v4" },
    ]
  }

  dpi = {
    enabled                = true
    fingerprinting_enabled = true
  }

  # Network app activity logs to Alloy's syslog VIP
  syslog = {
    enabled          = true
    ip               = local.lan.loadBalancerIPs.syslog
    port             = 5142
    log_all_contents = false
    contents         = ["admin_activity", "client", "critical", "device", "security_detections", "triggers", "updates", "vpn"]
    debug            = false
    netconsole = {
      enabled = false
    }
    this_controller = {
      enabled        = false
      encrypted_only = false
    }
  }
}
