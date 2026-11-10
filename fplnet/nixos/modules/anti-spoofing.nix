# edge forwards nothing that does not belong to us.
{
  config,
  lib,
  ...
}: let
  sitePrefixes = {
    wg-gw1-aah1 = ["2a0c:b641:f94::/48"];
  };

  networks = lib.attrValues config.systemd.network.networks;

  gatewayLinks = lib.filter (n: lib.hasPrefix "wg-gw1-" (n.matchConfig.Name or "")) networks;

  gatewayRule = n: let
    name = n.matchConfig.Name;
    prefixes = sitePrefixes.${name} or (throw "anti-spoofing: no site prefixes for ${name}");
  in ''
    iifname "${name}" ip6 saddr != { ${lib.concatStringsSep ", " (prefixes ++ n.address)} } counter name site_spoof drop
  '';

  # The router's own addresses, provider and IX ones included.
  hostAddresses = map (a: lib.head (lib.splitString "/" a)) (lib.concatMap (n: n.address or []) networks);
  # Addresses inside f90::/44 stay out, nft rejects overlapping set elements.
  v6 = ["::" "fe80::/10" "2a0c:b641:f90::/44"] ++ lib.filter (a: lib.hasInfix ":" a && !(lib.hasPrefix "2a0c:b641:f9" a)) hostAddresses;
  v4 = lib.filter (a: !(lib.hasInfix ":" a)) hostAddresses;
  set = lib.concatStringsSep ", ";
in {
  networking.nftables.tables.anti-spoofing = {
    family = "inet";
    content = ''
      counter site_spoof {}
      counter foreign_source {}
      counter own_source {}
      counter local_spoof {}

      # Our own space and ULAs never enter from outside, whether forwarded or for the router.
      chain prerouting {
        type filter hook prerouting priority filter; policy accept;
        iifname "lo" accept
        iifname "wg-er1-*" accept
        iifname "wg-gw1-*" accept
        ip6 saddr { 2a0c:b641:f90::/44, fc00::/7 } counter name own_source drop
      }

      chain forward {
        type filter hook forward priority filter; policy accept;
        ${lib.concatMapStrings gatewayRule gatewayLinks}
        oifname "wg-er1-*" accept
        oifname "wg-gw1-*" accept
        ip6 saddr != 2a0c:b641:f90::/44 counter name foreign_source drop
      }

      # The router itself only sends from its own addresses.
      chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" accept
        ip6 saddr != { ${set v6} } counter name local_spoof drop
        ${lib.optionalString (v4 != []) ''ip saddr != { ${set v4} } counter name local_spoof drop''}
      }
    '';
  };
}
