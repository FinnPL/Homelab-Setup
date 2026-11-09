{
  services.bird = {
    enable = true;
    config = ''
      # VULTR_PASSWORD, written by CI from kv/fplnet/bgp/er1-fra1
      include "secrets.conf";

      router id 209.250.233.8;

      define OWN_AS = 218255;
      define OWN_V6 = [ 2a0c:b641:f90::/48, 2a0c:b641:f94::/48 ];

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

      filter to_upstream {
        if net ~ OWN_V6 then accept;
        reject;
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

      # Vultr's route server, multihop from the main address.
      protocol bgp vultr_v6 {
        description "Vultr AS20473";
        local 2a05:f480:1800:28:5400:7ff:fe06:3983 as OWN_AS;
        neighbor 2001:19f0:ffff::1 as 64515;
        multihop 2;
        authentication md5;
        password VULTR_PASSWORD;
        ipv6 {
          import table on;
          import filter from_upstream;
          export filter to_upstream;
        };
      }
    '';

    # The real file only exists on the router.
    preCheckConfig = ''
      echo 'define VULTR_PASSWORD = "build-check";' > secrets.conf
    '';
  };

  environment.etc."bird/secrets.conf".source = "/var/lib/bird/secrets.conf";

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1003:: tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f90:1003:: udp dport 3784 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f90:1004:: tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f90:1004:: udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f90:1005::1 tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr 2a0c:b641:f90:1005::1 udp dport 3784 accept
    ip6 saddr 2001:19f0:ffff::1 tcp dport 179 accept
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
