{inventory, ...}: let
  inherit (inventory) address vieta;
  inherit (inventory.fplnet) asn prefixes routers links;
  host = routers.er1-ams1;
  dus1 = links."er1-dus1/er1-ams1".addresses;
  fra1 = links."er1-ams1/er1-fra1".addresses;
  gw1 = links."er1-ams1/gw1-aah1".addresses;
in {
  services.bird = {
    enable = true;
    config = ''
      router id ${address host.uplink.v4};

      define OWN_AS = ${toString asn};
      define OWN_V6 = [ ${host.prefix}, ${vieta.prefix}, ${prefixes.edgeAnycast}, ${prefixes.siteAnycast} ];

      protocol device {}

      # Default route for the sites; this kernel keeps its own.
      protocol static default_v6 {
        ipv6;
        route ::/0 unreachable;
      }

      # This edge's own /48
      protocol static own_v6 {
        ipv6;
        route ${host.prefix} unreachable;
      }

      protocol static loopback {
        ipv6;
        route ${host.loopback}/128 unreachable;
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
        if net = ${vieta.prefix} || net = ${prefixes.siteAnycast} then {
          bgp_path.prepend(OWN_AS);
          bgp_path.prepend(OWN_AS);
        }
        if net ~ OWN_V6 then accept;
        reject;
      }

      protocol bgp ibgp_dus1 {
        description "er1-dus1";
        local ${dus1.er1-ams1} as OWN_AS;
        neighbor ${dus1.er1-dus1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.er1-dus1.loopback}/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_fra1 {
        description "er1-fra1";
        local ${fra1.er1-ams1} as OWN_AS;
        neighbor ${fra1.er1-fra1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.er1-fra1.loopback}/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_gw1_aah1 {
        description "gw1-aah1";
        local ${gw1.er1-ams1} as OWN_AS;
        neighbor ${gw1.gw1-aah1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.gw1-aah1.loopback}/128 || net = ${vieta.prefix} || net ~ [ ${prefixes.siteAnycast}{128,128} ];
          export where proto = "loopback" || proto = "default_v6";
        };
      }

      # Paradox Networks route collectors, on-link in the uplink /48. No MD5.
      template bgp paradox {
        description "Paradox Networks AS52025";
        local ${address host.uplink.v6} as OWN_AS;
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
        local ${address host.interfaces.interix.v6} as OWN_AS;
        ipv6 {
          import table on;
          import filter from_route_server;
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
        local ${address host.interfaces.interix.v6} as OWN_AS;
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
        local ${address host.interfaces.interix.v6} as OWN_AS;
        neighbor 2001:7f8:134::bc as 6939;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_transit;
          receive limit 400000 action restart;
          export filter to_upstream;
        };
      }

      # Full table for HE's route collector
      filter to_collector {
        if net ~ OWN_V6 then accept;
        if net ~ [ ${prefixes.aggregate}+ ] then reject;
        if source != RTS_BGP || net = ::/0 then reject;
        # eBGP-learned only; iBGP carries just loopbacks, f94 and f92 addresses
        if bgp_path.len = 0 then reject;
        accept;
      }

      protocol bgp he_collector {
        description "HE route collector AS393338";
        local ${host.loopback} as OWN_AS;
        neighbor 2600:7000:1000::15 as 393338;
        multihop;
        ipv6 {
          import none;
          export filter to_collector;
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
    ip6 saddr 2600:7000:1000::15 tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr ${dus1.er1-dus1} tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr ${dus1.er1-dus1} udp dport 3784 accept
    iifname "wg-er1-fra1" ip6 saddr ${fra1.er1-fra1} tcp dport 179 accept
    iifname "wg-er1-fra1" ip6 saddr ${fra1.er1-fra1} udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr ${gw1.gw1-aah1} tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr ${gw1.gw1-aah1} udp dport 3784 accept
    ip6 saddr { 2602:fa7e:17::125, 2602:fa7e:17::126 } tcp dport 179 accept
    iifname "interix" ip6 saddr { 2001:7f8:134::253, 2001:7f8:134::254, 2001:7f8:134::40, 2001:7f8:134::bc } tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["${host.loopback}/128"];
    routes = [
      {
        Destination = host.prefix;
        Type = "unreachable";
      }
      {
        Destination = vieta.prefix;
        Type = "unreachable";
      }
    ];
  };
}
