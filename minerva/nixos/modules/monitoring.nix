# Exporters for Prometheus
{
  config,
  lib,
  ...
}: let
  cfg = config.minerva.monitoring;
in {
  options.minerva.monitoring.scrapeSources = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "IPv4 networks Prometheus scrapes from.";
  };

  config = {
    services.prometheus.exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd" "textfile"];
        extraFlags = ["--collector.textfile.directory=/var/lib/prometheus-node-exporter-text"];
      };
      smartctl.enable = true;
    };

    networking.firewall.extraInputRules = lib.mkIf (cfg.scrapeSources != []) ''
      ip saddr { ${lib.concatStringsSep ", " cfg.scrapeSources} } tcp dport { ${toString config.services.prometheus.exporters.node.port}, ${toString config.services.prometheus.exporters.smartctl.port} } accept
    '';
  };
}
