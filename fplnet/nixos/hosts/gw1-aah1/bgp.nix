{
  inventory,
  lib,
  ...
}: let
  inherit (inventory) address fplnet vieta;
  inherit (fplnet) prefixes routers links;
  host = routers.gw1-aah1;
  dus1 = links."er1-dus1/gw1-aah1".addresses;
  ams1 = links."er1-ams1/gw1-aah1".addresses;
  fra1 = links."er1-fra1/gw1-aah1".addresses;

  # Talos nodes by the last octet of their Athena IPv4 address, which is also their
  # IPv6 address f94:20::<octet> (vieta/02-infrastructure/talos-patches.tf).
  k8sNodes = lib.mapAttrs' (_: h: lib.nameValuePair (lib.last (lib.splitString "." h.ipv4)) h.k8sNode) (lib.filterAttrs (_: h: h ? k8sNode) vieta.hosts);
  nodeAddress = octet: "${lib.removeSuffix "/64" vieta.nodeNetwork}${octet}";

  # A node may announce its pod /64 and LoadBalancer /128s from f94:8000::/64 and the f92 site anycast.
  k8sSessions = lib.concatStrings (lib.mapAttrsToList (octet: name: ''
      protocol bgp k8s_${octet} from k8s {
        description "${name}";
        neighbor ${nodeAddress octet} as K8S_AS;
        ipv6 {
          import where net ~ [ ${vieta.podNetwork}{64,64}, ${vieta.publicServicePool}{128,128}, ${prefixes.siteAnycast}{128,128} ];
          import limit 32 action block;
          export none;
        };
      }
    '')
    k8sNodes);
in {
  services.bird = {
    enable = true;
    config = ''
      router id ${address host.uplink.v4};

      define OWN_AS = ${toString fplnet.asn};
      define K8S_AS = ${toString vieta.clusterAsn};

      protocol device {}

      protocol static loopback {
        ipv6;
        route ${host.loopback}/128 unreachable;
      }

      protocol static vieta {
        ipv6;
        route ${vieta.prefix} unreachable;
      }

      # Edge loopbacks, the default route and the cluster's routes reach the kernel.
      # The cluster's routes stay here: the edges only get the /48.
      protocol kernel {
        ipv6 {
          import none;
          export where proto = "ibgp_dus1" || proto = "ibgp_ams1" || proto = "ibgp_fra1" || proto ~ "k8s_*";
        };
      }

      protocol bfd {
        interface "wg-er1-*" {
          min rx interval 300 ms;
          min tx interval 300 ms;
          multiplier 5;
        };
      }

      # Default via er1-fra1 (~5 ms), then er1-dus1 (~20 ms), then er1-ams1 (~25 ms).
      filter from_edge {
        if !(net = ${routers.er1-dus1.loopback}/128 || net = ${routers.er1-ams1.loopback}/128 || net = ${routers.er1-fra1.loopback}/128 || net = ::/0) then reject;
        if proto = "ibgp_fra1" then bgp_local_pref = 200;
        if proto = "ibgp_dus1" then bgp_local_pref = 150;
        accept;
      }

      template bgp edge {
        direct;
        bfd on;
        ipv6 {
          next hop self;
          import filter from_edge;
          export where proto = "loopback" || proto = "vieta" || (proto ~ "k8s_*" && net ~ [ ${prefixes.siteAnycast}{128,128} ]);
        };
      }

      protocol bgp ibgp_dus1 from edge {
        description "er1-dus1";
        local ${dus1.gw1-aah1} as OWN_AS;
        neighbor ${dus1.er1-dus1} as OWN_AS;
      }

      protocol bgp ibgp_ams1 from edge {
        description "er1-ams1";
        local ${ams1.gw1-aah1} as OWN_AS;
        neighbor ${ams1.er1-ams1} as OWN_AS;
      }

      protocol bgp ibgp_fra1 from edge {
        description "er1-fra1";
        local ${fra1.gw1-aah1} as OWN_AS;
        neighbor ${fra1.er1-fra1} as OWN_AS;
      }

      # Cilium on each Talos node. Cilium only dials out, so gw1 waits.
      template bgp k8s {
        local ${address host.uplink.v6} as OWN_AS;
        direct;
        passive on;
        hold time 9;
        keepalive time 3;
        graceful restart on;
      }

      ${k8sSessions}
    '';
  };

  networking.firewall.extraInputRules = ''
    iifname "wg-er1-dus1" ip6 saddr ${dus1.er1-dus1} tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr ${dus1.er1-dus1} udp dport 3784 accept
    iifname "wg-er1-ams1" ip6 saddr ${ams1.er1-ams1} tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr ${ams1.er1-ams1} udp dport 3784 accept
    iifname "wg-er1-fra1" ip6 saddr ${fra1.er1-fra1} tcp dport 179 accept
    iifname "wg-er1-fra1" ip6 saddr ${fra1.er1-fra1} udp dport 3784 accept
    iifname "${host.uplink.interface}" ip6 saddr { ${lib.concatMapStringsSep ", " nodeAddress (lib.attrNames k8sNodes)} } tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["${host.loopback}/128"];
    routes = [
      {
        Destination = vieta.prefix;
        Type = "unreachable";
      }
    ];
  };
}
