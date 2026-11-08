{
  services.bird = {
    enable = true;
    config = ''
      router id 10.10.1.95;

      define OWN_AS = 218255;

      protocol device {}

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f90::11/128 unreachable;
      }

      protocol static vieta {
        ipv6;
        route 2a0c:b641:f94::/48 unreachable;
      }

      # Edge loopbacks and the default route reach the kernel.
      protocol kernel {
        ipv6 {
          import none;
          export where proto = "ibgp_dus1" || proto = "ibgp_ams1";
        };
      }

      protocol bfd {
        interface "wg-er1-*" {
          min rx interval 300 ms;
          min tx interval 300 ms;
          multiplier 5;
        };
      }

      # Default via er1-dus1 (closer); er1-ams1 takes over when BFD drops it.
      filter from_edge {
        if !(net = 2a0c:b641:f90::1/128 || net = 2a0c:b641:f90::2/128 || net = ::/0) then reject;
        if proto = "ibgp_dus1" then bgp_local_pref = 200;
        accept;
      }

      template bgp edge {
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import filter from_edge;
          export where proto = "loopback" || proto = "vieta";
        };
      }

      protocol bgp ibgp_dus1 from edge {
        description "er1-dus1";
        local 2a0c:b641:f90:1000::1 as OWN_AS;
        neighbor 2a0c:b641:f90:1000:: as OWN_AS;
      }

      protocol bgp ibgp_ams1 from edge {
        description "er1-ams1";
        local 2a0c:b641:f90:1002::1 as OWN_AS;
        neighbor 2a0c:b641:f90:1002:: as OWN_AS;
      }
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1000:: tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1000:: udp dport 3784 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f90:1002:: tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f90:1002:: udp dport 3784 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f90::11/128"];
    routes = [
      {
        Destination = "2a0c:b641:f94::/48";
        Type = "unreachable";
      }
    ];
  };
}
