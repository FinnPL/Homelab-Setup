{lib, ...}: let
  # Talos nodes by the last octet of their Athena IPv4 address, which is also their
  # IPv6 address f94:20::<octet> (02-infrastructure/talos-patches.tf).
  k8sNodes = {
    "60" = "talos-8vk-gus";
    "61" = "talos-m0l-ybl";
    "62" = "talos-ymz-dnc";
    "63" = "talos-urr-99l";
    "66" = "talos-4ut-tyx";
  };
  nodeAddress = octet: "2a0c:b641:f94:20::${octet}";

  # A node may announce its pod /64 and LoadBalancer /128s from f94:8000::/64.
  k8sSessions = lib.concatStrings (lib.mapAttrsToList (octet: name: ''
      protocol bgp k8s_${octet} from k8s {
        description "${name}";
        neighbor ${nodeAddress octet} as K8S_AS;
        ipv6 {
          import where net ~ [ 2a0c:b641:f94:8100::/56{64,64}, 2a0c:b641:f94:8000::/64{128,128} ];
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
      router id 10.10.1.95;

      define OWN_AS = 218255;
      define K8S_AS = 4200218255;

      protocol device {}

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f94::1/128 unreachable;
      }

      protocol static vieta {
        ipv6;
        route 2a0c:b641:f94::/48 unreachable;
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

      # Default via er1-dus1 (closer); er1-ams1 takes over when BFD drops it.
      filter from_edge {
        if !(net = 2a0c:b641:f98::1/128 || net = 2a0c:b641:f99::1/128 || net = 2a0c:b641:f9a::1/128 || net = ::/0) then reject;
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
        local 2a0c:b641:f98:1000::1 as OWN_AS;
        neighbor 2a0c:b641:f98:1000:: as OWN_AS;
      }

      protocol bgp ibgp_ams1 from edge {
        description "er1-ams1";
        local 2a0c:b641:f99:1000::1 as OWN_AS;
        neighbor 2a0c:b641:f99:1000:: as OWN_AS;
      }

      protocol bgp ibgp_fra1 from edge {
        description "er1-fra1";
        local 2a0c:b641:f9a:1000::1 as OWN_AS;
        neighbor 2a0c:b641:f9a:1000:: as OWN_AS;
      }

      # Cilium on each Talos node. Cilium only dials out, so gw1 waits.
      template bgp k8s {
        local 2a0c:b641:f94:20::1 as OWN_AS;
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
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f98:1000:: tcp dport 179 accept
    iifname "wg-er1-dus1" ip6 saddr 2a0c:b641:f98:1000:: udp dport 3784 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f99:1000:: tcp dport 179 accept
    iifname "wg-er1-ams1" ip6 saddr 2a0c:b641:f99:1000:: udp dport 3784 accept
    iifname "wg-er1-fra1" ip6 saddr 2a0c:b641:f9a:1000:: tcp dport 179 accept
    iifname "wg-er1-fra1" ip6 saddr 2a0c:b641:f9a:1000:: udp dport 3784 accept
    iifname "eth0" ip6 saddr { ${lib.concatMapStringsSep ", " nodeAddress (lib.attrNames k8sNodes)} } tcp dport 179 accept
  '';

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f94::1/128"];
    routes = [
      {
        Destination = "2a0c:b641:f94::/48";
        Type = "unreachable";
      }
    ];
  };
}
