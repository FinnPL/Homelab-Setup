# RPKI route origin validation on the edges.
{
  config,
  lib,
  ...
}: let
  cfg = config.fplnet.rpki;
  caches = {
    dus1 = "2a0c:b641:f98::1";
    ams1 = "2a0c:b641:f99::1";
  };
  edgeTunnels = lib.concatMapStringsSep ", " (name: ''"${name}"'') (
    lib.filter (lib.hasPrefix "wg-er1-")
    (lib.mapAttrsToList (_: netdev: netdev.netdevConfig.Name) config.systemd.network.netdevs)
  );
in {
  options.fplnet.rpki.validator = lib.mkEnableOption "a Routinator RTR cache for all edges";

  config = lib.mkMerge [
    {
      services.bird.config = lib.mkBefore ''
        roa6 table r6;

        ${lib.concatStrings (lib.mapAttrsToList (name: address: ''
            protocol rpki rpki_${name} {
              roa6 { table r6; };
              remote ${address} port 3323;
              retry keep 90;
              refresh keep 900;
              expire keep 172800;
            }
          '')
          caches)}
        # Our own space never arrives from outside; a forged origin of AS218255 would pass ROV.
        filter from_upstream {
          if net ~ [ 2a0c:b641:f90::/44+ ] then reject;
          if roa_check(r6, net, bgp_path.last_nonaggregated) = ROA_INVALID then reject;
          accept;
        }
      '';
    }

    (lib.mkIf cfg.validator {
      services.routinator = {
        enable = true;
        settings = {
          rtr-listen = ["[::]:3323"];
          http-listen = ["[::]:8323"];
        };
      };

      fplnet.monitoring.extraPorts = [8323];

      networking.firewall.extraInputRules = ''
        iifname { ${edgeTunnels} } tcp dport 3323 accept
      '';
    })
  ];
}
