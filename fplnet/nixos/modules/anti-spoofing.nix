# edge forwards nothing that does not belong to us.
{
  config,
  lib,
  ...
}: let
  sitePrefixes = {
    wg-gw1-aah1 = ["2a0c:b641:f94::/48"];
  };

  gatewayLinks =
    lib.filter (n: lib.hasPrefix "wg-gw1-" (n.matchConfig.Name or ""))
    (lib.attrValues config.systemd.network.networks);

  gatewayRule = n: let
    name = n.matchConfig.Name;
    prefixes = sitePrefixes.${name} or (throw "anti-spoofing: no site prefixes for ${name}");
  in ''
    iifname "${name}" ip6 saddr != { ${lib.concatStringsSep ", " (prefixes ++ n.address)} } counter name site_spoof drop
  '';
in {
  networking.nftables.tables.anti-spoofing = {
    family = "ip6";
    content = ''
      counter site_spoof {}
      counter foreign_source {}

      chain forward {
        type filter hook forward priority filter; policy accept;
        ${lib.concatMapStrings gatewayRule gatewayLinks}
        oifname "wg-er1-*" accept
        oifname "wg-gw1-*" accept
        ip6 saddr != 2a0c:b641:f90::/44 counter name foreign_source drop
      }
    '';
  };
}
