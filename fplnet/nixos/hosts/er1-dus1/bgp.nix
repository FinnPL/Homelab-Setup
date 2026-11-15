{inventory, ...}: let
  inherit (inventory) address vieta;
  inherit (inventory.fplnet) asn prefixes routers links;
  host = routers.er1-dus1;
  ams1 = links."er1-dus1/er1-ams1".addresses;
  fra1 = links."er1-dus1/er1-fra1".addresses;
  gw1 = links."er1-dus1/gw1-aah1".addresses;
in {
  services.bird = {
    enable = true;
    config = ''
      router id ${address host.uplink.v4};

      define OWN_AS = ${toString asn};
      define OWN_V6 = [ ${host.prefix}, ${vieta.prefix}, ${prefixes.edgeAnycast}, ${prefixes.siteAnycast} ];

      protocol device {}

      # This edge's own /48
      protocol static own_v6 {
        ipv6;
        route ${host.prefix} unreachable;
      }

      # Default route for the sites; this kernel keeps its own.
      protocol static default_v6 {
        ipv6;
        route ::/0 unreachable;
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
        }
        if net ~ OWN_V6 then accept;
        reject;
      }

      # Vieta and the anycast site only as a last resort over the tunnel.
      filter to_route64 {
        if net = ${vieta.prefix} || net = ${prefixes.edgeAnycast} || net = ${prefixes.siteAnycast} then {
          bgp_path.prepend(OWN_AS);
          bgp_path.prepend(OWN_AS);
          bgp_path.prepend(OWN_AS);
        }
        if net ~ OWN_V6 then accept;
        reject;
      }

      protocol bgp ibgp_ams1 {
        description "er1-ams1";
        local ${ams1.er1-dus1} as OWN_AS;
        neighbor ${ams1.er1-ams1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.er1-ams1.loopback}/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_fra1 {
        description "er1-fra1";
        local ${fra1.er1-dus1} as OWN_AS;
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
        local ${gw1.er1-dus1} as OWN_AS;
        neighbor ${gw1.gw1-aah1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.gw1-aah1.loopback}/128 || net = ${vieta.prefix} || net ~ [ ${prefixes.siteAnycast}{128,128} ];
          export where proto = "loopback" || proto = "default_v6";
        };
      }

      # Servperso session D_818_218255_6 on access2-dus-my.de.
      protocol bgp servperso_v6 {
        description "Servperso AS34872";
        local ${address host.uplink.v6} as OWN_AS;
        neighbor 2a0c:b640:11::ffff as 34872;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_transit;
          receive limit 400000 action restart;
          export filter to_upstream;
        };
      }

      # Route64 r4-fra-de over wg-r64-fra4 (route64.nix).
      protocol bgp route64_fra4 {
        description "Route64 AS212895";
        local ${address host.interfaces.wg-r64-fra4.v6} as OWN_AS;
        neighbor 2a11:6c7:f00:2b4::1 as 212895;
        enforce first as on;
        # Backup only
        default bgp_local_pref 80;
        ipv6 {
          import table on;
          import filter from_transit;
          receive limit 400000 action restart;
          export filter to_route64;
        };
      }

      # LocIX DUS route servers AS202409 on ens19 (locix.nix). No MD5.
      template bgp locix_rs {
        description "LocIX DUS RS AS202409";
        local ${address host.interfaces.ens19.v6} as OWN_AS;
        ipv6 {
          import table on;
          import filter from_route_server;
          receive limit 100000 action restart;
          export filter to_upstream;
        };
      }

      protocol bgp locix_rs1 from locix_rs {
        neighbor 2a0c:b641:701::a5:20:2409:1 as 202409;
      }

      protocol bgp locix_rs2 from locix_rs {
        neighbor 2a0c:b641:701::a5:20:2409:2 as 202409;
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
        neighbor 2600:7000:1000::11 as 393338;
        multihop;
        ipv6 {
          import none;
          export filter to_collector;
        };
      }
    '';
  };

  fplnet.monitoring.extraProbeTargets = [
    "2a0c:b640:11::ffff"
    "2a0c:b641:701::a5:20:2409:1"
    "2a0c:b641:701::a5:20:2409:2"
  ];

  networking.firewall.extraInputRules = ''
    ip6 saddr 2600:7000:1000::11 tcp dport 179 accept
    ip6 saddr 2a0c:b640:11::ffff tcp dport 179 accept
    iifname "wg-r64-fra4" ip6 saddr 2a11:6c7:f00:2b4::1 tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr ${ams1.er1-ams1} tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr ${ams1.er1-ams1} udp dport 3784 accept
    iifname "wg-er1-fra1" ip6 saddr ${fra1.er1-fra1} tcp dport 179 accept
    iifname "wg-er1-fra1" ip6 saddr ${fra1.er1-fra1} udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr ${gw1.gw1-aah1} tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr ${gw1.gw1-aah1} udp dport 3784 accept
    iifname "ens19" ip6 saddr { 2a0c:b641:701::a5:20:2409:1, 2a0c:b641:701::a5:20:2409:2 } tcp dport 179 accept
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
