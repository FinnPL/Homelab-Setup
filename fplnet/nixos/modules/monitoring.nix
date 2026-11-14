# Prometheus exporters on the router's loopback, scraped by Vieta's Prometheus.
# Only the cluster's pod range may connect, and only through backbone tunnels.
{
  config,
  lib,
  pkgs,
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

    systemd.services.smokeping-watchdog = {
      description = "Restart smokeping_prober when it stopped pinging a target";
      after = ["prometheus-smokeping-exporter.service"];
      path = [pkgs.curl pkgs.gawk pkgs.coreutils pkgs.systemd];
      serviceConfig.Type = "oneshot";
      script = ''
        state=/run/smokeping-watchdog
        now=$(curl -sf "http://[${loopback}]:9374/metrics" | awk '/^smokeping_requests_total/ {print $1, $2}' | sort) || exit 0
        [ -n "$now" ] || exit 0
        if [ -f "$state" ]; then
          stuck=$(join "$state" <(echo "$now") | awk '$2 == $3 {print $1}')
          if [ -n "$stuck" ]; then
            echo "not pinging: $stuck"
            rm -f "$state"
            systemctl restart prometheus-smokeping-exporter.service
            exit 0
          fi
        fi
        echo "$now" > "$state"
      '';
    };
    systemd.timers.smokeping-watchdog = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = "2min";
      };
    };

    networking.firewall.extraInputRules = ''
      iifname { ${interfaces} } ip6 saddr 2a0c:b641:f94:8100::/56 tcp dport { ${lib.concatMapStringsSep ", " toString ([9100 9324 9374] ++ cfg.extraPorts)} } accept
    '';
  };
}
