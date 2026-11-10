{
  services.bird = {
    enable = true;
    config = ''
      router id 188.65.164.27;

      define OWN_AS = 218255;
      define OWN_V6 = [ 2a0c:b641:f99::/48, 2a0c:b641:f94::/48 ];

      protocol device {}

      # Default route for the sites; this kernel keeps its own.
      protocol static default_v6 {
        ipv6;
        route ::/0 unreachable;
      }

      # This edge's own /48
      protocol static own_v6 {
        ipv6;
        route 2a0c:b641:f99::/48 unreachable;
      }

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f99::1/128 unreachable;
      }

      # Only peer loopbacks and site prefixes reach the kernel.
      protocol kernel {
        ipv6 {
          import none;
          export where proto = "ibgp_dus1" || proto = "ibgp_fra1" || proto = "ibgp_gw1_aah1";
        };
      }

      # Drops iBGP within 1.5 s of the tunnel failing
      protocol bfd {
        interface "wg-er1-*", "wg-gw1-*" {
          min rx interval 300 ms;
          min tx interval 300 ms;
          multiplier 5;
        };
      }

      filter to_upstream {
        if net ~ OWN_V6 then accept;
        reject;
      }

      protocol bgp ibgp_dus1 {
        description "er1-dus1";
        local 2a0c:b641:f98:1001::1 as OWN_AS;
        neighbor 2a0c:b641:f98:1001:: as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f98::1/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_fra1 {
        description "er1-fra1";
        local 2a0c:b641:f99:1001:: as OWN_AS;
        neighbor 2a0c:b641:f99:1001::1 as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f9a::1/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_gw1_aah1 {
        description "gw1-aah1";
        local 2a0c:b641:f99:1000:: as OWN_AS;
        neighbor 2a0c:b641:f99:1000::1 as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f94::1/128 || net = 2a0c:b641:f94::/48;
          export where proto = "loopback" || proto = "default_v6";
        };
      }

      # Paradox Networks route collectors, on-link in the uplink /48. No MD5.
      template bgp paradox {
        description "Paradox Networks AS52025";
        local 2602:fa7e:17::3f as OWN_AS;
        hold time 90;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_transit;
          receive limit 400000 action restart;
          export filter to_upstream;
        };
      }

      protocol bgp paradox_rc1 from paradox {
        neighbor 2602:fa7e:17::125 as 52025;
      }

      protocol bgp paradox_rc2 from paradox {
        neighbor 2602:fa7e:17::126 as 52025;
      }

      # InterIX route servers AS56584 on interix
      template bgp interix_rs {
        description "InterIX RS AS56584";
        local 2001:7f8:134::10e as OWN_AS;
        ipv6 {
          import table on;
          import filter from_peer;
          receive limit 100000 action restart;
          export filter to_upstream;
        };
      }

      protocol bgp interix_rs1 from interix_rs {
        neighbor 2001:7f8:134::253 as 56584;
      }

      protocol bgp interix_rs2 from interix_rs {
        neighbor 2001:7f8:134::254 as 56584;
      }

      # Cloudflare Bilateral at InterIX.
      protocol bgp cloudflare {
        description "Cloudflare AS13335";
        local 2001:7f8:134::10e as OWN_AS;
        neighbor 2001:7f8:134::40 as 13335;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_peer;
          receive limit 30000 action restart;
          export filter to_upstream;
        };
      }

      # Hurricane Electric transit at InterIX.
      protocol bgp he {
        description "Hurricane Electric AS6939";
        local 2001:7f8:134::10e as OWN_AS;
        neighbor 2001:7f8:134::bc as 6939;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_transit;
          receive limit 400000 action restart;
          export filter to_upstream;
        };
      }
    '';
  };

  fplnet.monitoring.extraProbeTargets = [
    "2602:fa7e:17::125"
    "2602:fa7e:17::126"
    "2001:7f8:134::253"
    "2001:7f8:134::254"
    "2001:7f8:134::40"
    "2001:7f8:134::bc"
  ];

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f98:1001:: tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f98:1001:: udp dport 3784 accept
    iifname "wg-er1-fra1" ip6 saddr 2a0c:b641:f99:1001::1 tcp dport 179 accept
    iifname "wg-er1-fra1" ip6 saddr 2a0c:b641:f99:1001::1 udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f99:1000::1 tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f99:1000::1 udp dport 3784 accept
    ip6 saddr { 2602:fa7e:17::125, 2602:fa7e:17::126 } tcp dport 179 accept
    iifname "interix" ip6 saddr { 2001:7f8:134::253, 2001:7f8:134::254, 2001:7f8:134::40, 2001:7f8:134::bc } tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f99::1/128"];
    routes = [
      {
        Destination = "2a0c:b641:f99::/48";
        Type = "unreachable";
      }
      {
        Destination = "2a0c:b641:f94::/48";
        Type = "unreachable";
      }
    ];
  };
}
