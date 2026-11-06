{
  services.bird = {
    enable = true;
    config = ''
      router id 188.65.164.27;

      define OWN_AS = 218255;

      protocol device {}

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f90::2/128 unreachable;
      }

      # Only the peer's loopback reaches the kernel.
      protocol kernel {
        ipv6 {
          import none;
          export where proto = "ibgp_dus1" && net = 2a0c:b641:f90::1/128;
        };
      }

      # The /48 is learned here, not originated: an upstream export of it ends with the tunnel.
      protocol bgp ibgp_dus1 {
        description "er1-dus1";
        local 2a0c:b641:f90:1001::1 as OWN_AS;
        neighbor 2a0c:b641:f90:1001:: as OWN_AS;
        direct;
        ipv6 {
          next hop self;
          import where net = 2a0c:b641:f90::1/128 || net = 2a0c:b641:f90::/48;
          export where proto = "loopback";
        };
      }
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1001:: tcp dport 179 accept
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
