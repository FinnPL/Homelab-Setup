# Prometheus exporters on the router's loopback, scraped by Vieta's Prometheus.
# Only the cluster's pod range may connect, and only through backbone tunnels.
{
  config,
  lib,
  ...
}: let
  cfg = config.fplnet.monitoring;
  loopback = lib.removeSuffix "/128" (lib.head config.systemd.network.networks."05-lo".address);
  backbone =
    lib.filter (name: lib.hasPrefix "wg-er1-" name || lib.hasPrefix "wg-gw1-" name)
    (lib.mapAttrsToList (_: netdev: netdev.netdevConfig.Name) config.systemd.network.netdevs);
  interfaces = lib.concatMapStringsSep ", " (name: ''"${name}"'') (backbone ++ cfg.extraInterfaces);

  # The far end of each backbone tunnel, by its name in fplnet/terraform/dns.tf:
  # er1-dus1's wg-er1-ams1 reaches wg-er1-dus1.er1.ams1.fplnet.net.
  linkPeer = tunnel: "wg-${config.networking.hostName}.${lib.replaceStrings ["-"] ["."] (lib.removePrefix "wg-" tunnel)}.fplnet.net";
in {
  options.fplnet.monitoring = {
    extraInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Interfaces besides the backbone tunnels that scrapes arrive on.";
    };
    extraPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [];
      description = "Metrics ports of other services on this router, opened like the exporters'.";
    };
    extraProbeTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Upstream and IX neighbours, pinged like the backbone peers.";
    };
  };

  config = {
    services.prometheus.exporters = {
      node = {
        enable = true;
        listenAddress = "[${loopback}]";
        enabledCollectors = ["systemd"];
      };
      bird = {
        enable = true;
        listenAddress = "[${loopback}]";
      };
      smokeping = {
        enable = true;
        listenAddress = "[${loopback}]";
        hosts = map linkPeer backbone ++ cfg.extraProbeTargets ++ ["2606:4700:4700::1111"];
      };
    };

    networking.firewall.extraInputRules = ''
      iifname { ${interfaces} } ip6 saddr 2a0c:b641:f94:8100::/56 tcp dport { ${lib.concatMapStringsSep ", " toString ([9100 9324 9374] ++ cfg.extraPorts)} } accept
    '';
  };
}
