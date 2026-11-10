{
  services.bird = {
    enable = true;
    config = ''
      router id 194.28.99.178;

      define OWN_AS = 218255;
      define OWN_V6 = [ 2a0c:b641:f98::/48, 2a0c:b641:f94::/48 ];

      protocol device {}

      # This edge's own /48
      protocol static own_v6 {
        ipv6;
        route 2a0c:b641:f98::/48 unreachable;
      }

      # Default route for the sites; this kernel keeps its own.
      protocol static default_v6 {
        ipv6;
        route ::/0 unreachable;
      }

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f98::1/128 unreachable;
      }

      # Only peer loopbacks and site prefixes reach the kernel.
      protocol kernel {
        ipv6 {
          import none;
          export where proto = "ibgp_ams1" || proto = "ibgp_fra1" || proto = "ibgp_gw1_aah1";
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

      protocol bgp ibgp_ams1 {
        description "er1-ams1";
        local 2a0c:b641:f98:1001:: as OWN_AS;
        neighbor 2a0c:b641:f98:1001::1 as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f99::1/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_fra1 {
        description "er1-fra1";
        local 2a0c:b641:f98:1002:: as OWN_AS;
        neighbor 2a0c:b641:f98:1002::1 as OWN_AS;
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
        local 2a0c:b641:f98:1000:: as OWN_AS;
        neighbor 2a0c:b641:f98:1000::1 as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f94::1/128 || net = 2a0c:b641:f94::/48;
          export where proto = "loopback" || proto = "default_v6";
        };
      }

      # Servperso session D_818_218255_6 on access2-dus-my.de.
      protocol bgp servperso_v6 {
        description "Servperso AS34872";
        local 2a0c:b640:11:178::1 as OWN_AS;
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
        local 2a11:6c7:f00:2b4::2 as OWN_AS;
        neighbor 2a11:6c7:f00:2b4::1 as 212895;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_transit;
          receive limit 400000 action restart;
          export filter to_upstream;
        };
      }

      # LocIX DUS route servers AS202409 on ens19 (locix.nix). No MD5.
      template bgp locix_rs {
        description "LocIX DUS RS AS202409";
        local 2a0c:b641:701::a5:21:8255:1 as OWN_AS;
        ipv6 {
          import table on;
          import filter from_peer;
          receive limit 20000 action restart;
          export filter to_upstream;
        };
      }

      protocol bgp locix_rs1 from locix_rs {
        neighbor 2a0c:b641:701::a5:20:2409:1 as 202409;
      }

      protocol bgp locix_rs2 from locix_rs {
        neighbor 2a0c:b641:701::a5:20:2409:2 as 202409;
      }
    '';
  };

  fplnet.monitoring.extraProbeTargets = [
    "2a0c:b640:11::ffff"
    "2a0c:b641:701::a5:20:2409:1"
    "2a0c:b641:701::a5:20:2409:2"
  ];

  networking.firewall.extraInputRules = ''
    ip6 saddr 2a0c:b640:11::ffff tcp dport 179 accept
    iifname "wg-r64-fra4" ip6 saddr 2a11:6c7:f00:2b4::1 tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f98:1001::1 tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f98:1001::1 udp dport 3784 accept
    iifname "wg-er1-fra1" ip6 saddr 2a0c:b641:f98:1002::1 tcp dport 179 accept
    iifname "wg-er1-fra1" ip6 saddr 2a0c:b641:f98:1002::1 udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f98:1000::1 tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f98:1000::1 udp dport 3784 accept
    iifname "ens19" ip6 saddr { 2a0c:b641:701::a5:20:2409:1, 2a0c:b641:701::a5:20:2409:2 } tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f98::1/128"];
    routes = [
      {
        Destination = "2a0c:b641:f98::/48";
        Type = "unreachable";
      }
      {
        Destination = "2a0c:b641:f94::/48";
        Type = "unreachable";
      }
    ];
  };
}
