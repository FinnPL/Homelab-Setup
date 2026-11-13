# Minerva pulls and no source can write to it
# nas/backup/<name>, one directory per remote path
# The pull runs as an unprivileged user: it can change the live copy, never the snapshots.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.minerva.backupPulls;
  stateDir = "/var/lib/backup-pull";
  key = "${stateDir}/id_ed25519";
  inherit (config.minerva.monitoring) textfileDir;
  zfs = config.boot.zfs.package;

  pullScript = name: pull: let
    ssh = lib.concatStringsSep " " [
      "ssh -i ${key}"
      "-o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"
      "-o UserKnownHostsFile=${pull.knownHosts} -o GlobalKnownHostsFile=/dev/null"
    ];
  in
    lib.concatMapStringsSep "\n" (path: let
      src = lib.removeSuffix "/" path;
    in ''
      rsync --archive --hard-links --numeric-ids --fake-super \
        --delete --delete-delay --max-delete=${toString pull.maxDelete} --bwlimit=${pull.bwlimit} \
        ${lib.concatMapStringsSep " " (e: "--exclude=${lib.escapeShellArg e}") pull.excludes} \
        -e ${lib.escapeShellArg ssh} \
        ${lib.escapeShellArg "${pull.user}@${pull.host}:${src}/"} \
        ${lib.escapeShellArg "/nas/backup/${name}/${baseNameOf src}/"}
    '')
    pull.paths;

  metric = name:
    pkgs.writeShellScript "backup-pull-${name}-metric" ''
      f=${textfileDir}/backup_pull_${name}.prom
      echo "backup_pull_last_success_timestamp_seconds{source=\"${name}\"} $(date +%s)" > "$f.tmp"
      mv "$f.tmp" "$f"
    '';
in {
  options.minerva.backupPulls = lib.mkOption {
    description = "Sources mirrored over rsync+SSH with a read-only account on the source.";
    default = {};
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        host = lib.mkOption {type = lib.types.str;};
        user = lib.mkOption {type = lib.types.str;};
        knownHosts = lib.mkOption {
          type = lib.types.path;
          description = "Pinned host key of the source.";
        };
        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Remote paths; a source without paths gets its dataset and key but no timer.";
        };
        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 03:00:00";
        };
        maxDelete = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1000;
          description = "Deletions per run (mass deletion, ransomware renames); past it rsync skips the rest and exits 25, so the unit fails.";
        };
        bwlimit = lib.mkOption {
          type = lib.types.str;
          default = "0";
        };
        excludes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "rsync --exclude patterns, e.g. the source's own metadata or snapshot folders.";
        };
      };
    });
  };

  config = lib.mkIf (cfg != {}) {
    users.users.backup-pull = {
      isSystemUser = true;
      group = "backup-pull";
      home = stateDir;
    };
    users.groups.backup-pull = {};

    systemd.services =
      {
        # The private half never leaves the VM. Authorize the .pub on each source's account.
        backup-pull-key = {
          description = "Create the backup pull SSH key";
          wantedBy = ["multi-user.target"];
          unitConfig.ConditionPathExists = "!${key}";
          path = [pkgs.openssh];
          serviceConfig = {
            Type = "oneshot";
            User = "backup-pull";
            StateDirectory = "backup-pull";
            StateDirectoryMode = "0700";
          };
          script = ''ssh-keygen -q -t ed25519 -N "" -C "backup-pull@nas.minerva" -f ${key}'';
        };
      }
      // lib.concatMapAttrs (name: pull: {
        "backup-pull-${name}-dataset" = {
          description = "Dataset nas/backup/${name}";
          wantedBy = ["multi-user.target"];
          after = ["zfs-import.target" "zfs-mount.service"];
          requires = ["zfs-mount.service"];
          path = [zfs];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            zfs list -H nas/backup/${name} >/dev/null 2>&1 || zfs create nas/backup/${name}
            chown backup-pull:backup-pull /nas/backup/${name}
            chmod 0750 /nas/backup/${name}
            # Lets an alert tell "never succeeded" from "not set up yet".
            echo 'backup_pull_configured{source="${name}"} ${
              if pull.paths != []
              then "1"
              else "0"
            }' > ${textfileDir}/backup_pull_${name}_config.prom
          '';
        };

        "backup-pull-${name}" = {
          description = "Pull ${name} into nas/backup/${name}";
          wants = ["network-online.target"];
          requires = ["backup-pull-${name}-dataset.service" "backup-pull-key.service"];
          after = ["network-online.target" "backup-pull-${name}-dataset.service" "backup-pull-key.service"];
          path = [pkgs.rsync pkgs.openssh];
          serviceConfig = {
            Type = "oneshot";
            User = "backup-pull";
            Group = "backup-pull";
            StateDirectory = "backup-pull";
            StateDirectoryMode = "0700";
            Nice = 10;
            IOSchedulingClass = "idle";
            ExecStartPost = "+${metric name}";
            ProtectSystem = "strict";
            ReadWritePaths = ["/nas/backup/${name}"];
            ProtectHome = true;
            PrivateTmp = true;
            NoNewPrivileges = true;
          };
          script = ''
            set -euo pipefail
            ${pullScript name pull}
          '';
        };
      })
      cfg;

    systemd.timers = lib.mapAttrs' (name: pull:
      lib.nameValuePair "backup-pull-${name}" {
        description = "Scheduled pull of ${name}";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = pull.onCalendar;
          Persistent = true;
          RandomizedDelaySec = "15min";
        };
      }) (lib.filterAttrs (_: pull: pull.paths != []) cfg);
  };
}
