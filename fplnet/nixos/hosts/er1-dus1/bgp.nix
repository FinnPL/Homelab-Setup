{
  services.bird = {
    enable = true;
    config = ''
      router id 194.28.99.178;

      define OWN_AS = 218255;
      define OWN_V6 = [ 2a0c:b641:f90::/48 ];

      protocol device {}

      protocol static own_v6 {
        ipv6;
        route 2a0c:b641:f90::/48 unreachable;
      }

      filter to_upstream {
        if net ~ OWN_V6 then accept;
        reject;
      }

      # Servperso session D_818_218255_6 on access2-dus-my.de.
      protocol bgp servperso_v6 {
        description "Servperso AS34872";
        local 2a0c:b640:11:178::1 as OWN_AS;
        neighbor 2a0c:b640:11::ffff as 34872;
        ipv6 {
          import all;
          export filter to_upstream;
        };
      }

      # Route64 r4-fra-de over wg-r64-fra4 (route64.nix).
      protocol bgp route64_fra4 {
        description "Route64 AS212895";
        local 2a11:6c7:f00:2b4::2 as OWN_AS;
        neighbor 2a11:6c7:f00:2b4::1 as 212895;
        ipv6 {
          import all;
          export filter to_upstream;
        };
      }
    '';
  };

  networking.firewall.extraInputRules = ''
    ip6 saddr 2a0c:b640:11::ffff tcp dport 179 accept
    iifname "wg-r64-fra4" ip6 saddr 2a11:6c7:f00:2b4::1 tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f90::1/128"];
    routes = [
      {
        Destination = "2a0c:b641:f90::/48";
        Type = "unreachable";
      }
    ];
  };
}
