{
  services.bird = {
    enable = true;
    config = ''
      router id 209.250.233.8;

      define OWN_AS = 218255;

      protocol device {}

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f90::3/128 unreachable;
      }

      # Only peer loopbacks and site prefixes reach the kernel.
      protocol kernel {
        ipv6 {
          import none;
          export where (proto = "ibgp_dus1" && net = 2a0c:b641:f90::1/128) || proto = "ibgp_ams1" || proto = "ibgp_gw1_aah1";
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

      # The /48 is learned here, not originated: an upstream export of it ends with the tunnel.
      protocol bgp ibgp_dus1 {
        description "er1-dus1";
        local 2a0c:b641:f90:1003::1 as OWN_AS;
        neighbor 2a0c:b641:f90:1003:: as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f90::1/128 || net = 2a0c:b641:f90::/48;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_ams1 {
        description "er1-ams1";
        local 2a0c:b641:f90:1004::1 as OWN_AS;
        neighbor 2a0c:b641:f90:1004:: as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f90::2/128;
          export where proto = "loopback";
        };
      }

      # No default to gw1 until this edge has an upstream.
      protocol bgp ibgp_gw1_aah1 {
        description "gw1-aah1";
        local 2a0c:b641:f90:1005:: as OWN_AS;
        neighbor 2a0c:b641:f90:1005::1 as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f90::11/128 || net = 2a0c:b641:f94::/48;
          export where proto = "loopback";
        };
      }
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1003:: tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1003:: udp dport 3784 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f90:1004:: tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f90:1004:: udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f90:1005::1 tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f90:1005::1 udp dport 3784 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f90::3/128"];
    routes = [
      {
        Destination = "2a0c:b641:f90::/48";
        Type = "unreachable";
      }
      {
        Destination = "2a0c:b641:f94::/48";
        Type = "unreachable";
      }
    ];
  };
}
