{
  services.bird = {
    enable = true;
    config = ''
      router id 188.65.164.27;

      define OWN_AS = 218255;
      define OWN_V6 = [ 2a0c:b641:f90::/48 ];

      protocol device {}

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f90::2/128 unreachable;
      }

      # Only the peer's loopback reaches the kernel.
      protocol kernel {
        ipv6 {
          import none;
          export where (proto = "ibgp_dus1" && net = 2a0c:b641:f90::1/128) || proto = "ibgp_gw1_aah1";
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

      # The /48 is learned here, not originated: an upstream export of it ends with the tunnel.
      protocol bgp ibgp_dus1 {
        description "er1-dus1";
        local 2a0c:b641:f90:1001::1 as OWN_AS;
        neighbor 2a0c:b641:f90:1001:: as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f90::1/128 || net = 2a0c:b641:f90::/48;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_gw1_aah1 {
        description "gw1-aah1";
        local 2a0c:b641:f90:1002:: as OWN_AS;
        neighbor 2a0c:b641:f90:1002::1 as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f90::11/128;
          export where proto = "loopback";
        };
      }

      # Paradox Networks route collectors, on-link in the uplink /48. No MD5.
      template bgp paradox {
        description "Paradox Networks AS52025";
        local 2602:fa7e:17::3f as OWN_AS;
        hold time 90;
        ipv6 {
          import all;
          export filter to_upstream;
        };
      }

      protocol bgp paradox_rc1 from paradox {
        neighbor 2602:fa7e:17::125 as 52025;
      }

      protocol bgp paradox_rc2 from paradox {
        neighbor 2602:fa7e:17::126 as 52025;
      }
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1001:: tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1001:: udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f90:1002::1 tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f90:1002::1 udp dport 3784 accept
    ip6 saddr { 2602:fa7e:17::125, 2602:fa7e:17::126 } tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f90::2/128"];
    routes = [
      {
        Destination = "2a0c:b641:f90::/48";
        Type = "unreachable";
      }
    ];
  };
}
