# Exporters for Prometheus
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.minerva.monitoring;
  zfs = config.boot.zfs.package;

  nasMetrics = pkgs.writeShellApplication {
    name = "nas-metrics";
    runtimeInputs = [zfs pkgs.jq pkgs.smartmontools pkgs.storcli pkgs.coreutils pkgs.gawk];
    text = ''
      out=${cfg.textfileDir}/nas.prom
      tmp=$(mktemp -p ${cfg.textfileDir} .nas.prom.XXXXXX)
      trap 'rm -f "$tmp"' EXIT

      status=$(zpool status -jp --json-int)
      {
        jq -r '
          .pools[] | . as $p | "pool=\"\($p.name)\"" as $l |
          "zfs_pool_online{\($l)} \(if $p.state == "ONLINE" then 1 else 0 end)",
          "zfs_pool_data_errors{\($l)} \($p.error_count)",
          ($p.scan_stats // empty | select(.function == "SCRUB") |
            "zfs_pool_scrub_end_timestamp_seconds{\($l)} \(.end_time)",
            "zfs_pool_scrub_errors{\($l)} \(.errors)",
            "zfs_pool_scrub_running{\($l)} \(if .state == "SCANNING" then 1 else 0 end)"),
          ($p.vdevs[] | .. | objects | select(.vdev_type? == "disk") |
            "\($l),disk=\"\(.name)\"" as $d |
            "zfs_disk_online{\($d)} \(if .state == "ONLINE" then 1 else 0 end)",
            "zfs_disk_errors{\($d),type=\"read\"} \(.read_errors)",
            "zfs_disk_errors{\($d),type=\"write\"} \(.write_errors)",
            "zfs_disk_errors{\($d),type=\"checksum\"} \(.checksum_errors)")
        ' <<<"$status"

        zpool list -Hp -o name,size,alloc | awk '{
          printf "zfs_pool_size_bytes{pool=\"%s\"} %s\n", $1, $2
          printf "zfs_pool_allocated_bytes{pool=\"%s\"} %s\n", $1, $3
        }'

        zfs list -Hp -t snapshot -o name,creation | awk '{
          split($1, s, "@"); if ($2 > newest[s[1]]) newest[s[1]] = $2
        } END {
          for (d in newest) printf "zfs_snapshot_newest_timestamp_seconds{dataset=\"%s\"} %s\n", d, newest[d]
        }'

        # SCSI self-test log, newest entry first; hours compare with the drive's own power-on clock.
        # nas_disk_info maps the pool's disk name to the serial and to smartctl_exporter's device.
        for disk in $(jq -r '.pools[].vdevs[] | .. | objects | select(.vdev_type? == "disk") | .name' <<<"$status"); do
          # smartctl's exit code is a bit mask; these drives always set bit 2.
          smart=$(smartctl -j -a "/dev/disk/by-id/$disk" || true)
          dev=$(basename "$(readlink -f "/dev/disk/by-id/$disk")")
          jq -r --arg d "$disk" --arg dev "$dev" '
            "disk=\"\($d)\"" as $l |
            "nas_disk_info{\($l),device=\"\($dev)\",serial=\"\(.serial_number)\"} 1",
            (.power_on_time.hours // empty | "smart_power_on_hours{\($l)} \(.)"),
            (.scsi_self_test_0 // empty |
              "smart_selftest_last_result{\($l),type=\"\(.code.string)\"} \(.result.value)",
              "smart_selftest_last_power_on_hours{\($l)} \(.power_on_time.hours)")
          ' <<<"$smart"
        done

        storcli /c0 show temperature J | jq -r '
          .Controllers[0]."Response Data"."Controller Properties"[]
          | select(.Ctrl_Prop | startswith("ROC temperature"))
          | "hba_roc_temperature_celsius{controller=\"0\"} \(.Value)"'

        echo "nas_metrics_last_success_timestamp_seconds $(date +%s)"
      } >"$tmp"

      chmod 0644 "$tmp"
      mv "$tmp" "$out"
    '';
  };
in {
  options.minerva.monitoring = {
    scrapeSources = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "IPv4 networks Prometheus scrapes from.";
    };
    textfileDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/prometheus-node-exporter-text";
      readOnly = true;
      description = "Directory node_exporter's textfile collector reads *.prom files from.";
    };
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "storcli";

    services.prometheus.exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd" "textfile"];
        extraFlags = ["--collector.textfile.directory=${cfg.textfileDir}"];
      };
      smartctl.enable = true;
    };

    systemd.tmpfiles.rules = ["d ${cfg.textfileDir} 0755 root root -"];

    systemd.services.nas-metrics = {
      description = "Write pool, disk and HBA metrics for node_exporter";
      after = ["zfs-import.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe nasMetrics;
        WorkingDirectory = "/tmp";
        ProtectSystem = "strict";
        ReadWritePaths = [cfg.textfileDir];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.nas-metrics = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "5min";
      };
    };

    networking.firewall.extraInputRules = lib.mkIf (cfg.scrapeSources != []) ''
      ip saddr { ${lib.concatStringsSep ", " cfg.scrapeSources} } tcp dport { ${toString config.services.prometheus.exporters.node.port}, ${toString config.services.prometheus.exporters.smartctl.port} } accept
    '';
  };
}
