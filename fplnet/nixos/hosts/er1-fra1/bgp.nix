{inventory, ...}: let
  inherit (inventory) address vieta;
  inherit (inventory.fplnet) asn prefixes routers links;
  host = routers.er1-fra1;
  dus1 = links."er1-dus1/er1-fra1".addresses;
  ams1 = links."er1-ams1/er1-fra1".addresses;
  gw1 = links."er1-fra1/gw1-aah1".addresses;
in {
  services.bird = {
    enable = true;
    config = ''
      # VULTR_PASSWORD, written by CI from kv/fplnet/bgp/er1-fra1
      include "secrets.conf";

      router id ${address host.uplink.v4};

      define OWN_AS = ${toString asn};
      define OWN_V6 = [ ${host.prefix}, ${vieta.prefix}, ${prefixes.edgeAnycast}, ${prefixes.siteAnycast} ];

      protocol device {}

      # Default route for the sites
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
        if net ~ OWN_V6 then accept;
        reject;
      }

      protocol bgp ibgp_dus1 {
        description "er1-dus1";
        local ${dus1.er1-fra1} as OWN_AS;
        neighbor ${dus1.er1-dus1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.er1-dus1.loopback}/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_ams1 {
        description "er1-ams1";
        local ${ams1.er1-fra1} as OWN_AS;
        neighbor ${ams1.er1-ams1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.er1-ams1.loopback}/128;
          export where proto = "loopback";
        };
      }

      protocol bgp ibgp_gw1_aah1 {
        description "gw1-aah1";
        local ${gw1.er1-fra1} as OWN_AS;
        neighbor ${gw1.gw1-aah1} as OWN_AS;
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import where net = ${routers.gw1-aah1.loopback}/128 || net = ${vieta.prefix} || net ~ [ ${prefixes.siteAnycast}{128,128} ];
          export where proto = "loopback" || proto = "default_v6";
        };
      }

      # Vultr's multihop neighbour, so its next hop resolves without the BGP /48 that contains it.
      protocol static vultr_nexthop {
        ipv6;
        route 2001:19f0:ffff::1/128 via fe80::fc00:7ff:fe06:3983%${host.uplink.interface};
      }

      # Vultr's private ASNs lead every path
      filter from_vultr {
        bgp_path.delete([64515, 65534]);
        if !import_ok(true) then reject;
        import_tag();
        bgp_large_community.add((${toString asn}, 2, 1));
        accept;
      }

      # Vultr's route server, multihop from the main address.
      protocol bgp vultr_v6 {
        description "Vultr AS20473";
        local ${address host.uplink.v6} as OWN_AS;
        neighbor 2001:19f0:ffff::1 as 64515;
        multihop 2;
        authentication md5;
        password VULTR_PASSWORD;
        enforce first as on;
        ipv6 {
          import table on;
          import filter from_vultr;
          receive limit 400000 action restart;
          export filter to_upstream;
        };
      }

      # Full table for HE's route collector AS393338
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
        neighbor 2600:7000:1000::12 as 393338;
        multihop;
        ipv6 {
          import none;
          export filter to_collector;
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
    ip6 saddr 2600:7000:1000::12 tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr ${dus1.er1-dus1} tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr ${dus1.er1-dus1} udp dport 3784 accept
    iifname "wg-er1-ams1" ip6 saddr ${ams1.er1-ams1} tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr ${ams1.er1-ams1} udp dport 3784 accept
    iifname "wg-gw1-aah1" ip6 saddr ${gw1.gw1-aah1} tcp dport 179 accept
    iifname "wg-gw1-aah1" ip6 saddr ${gw1.gw1-aah1} udp dport 3784 accept
    ip6 saddr 2001:19f0:ffff::1 tcp dport 179 accept
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
