# Vieta's FPLNET gateway: unprivileged LXC on the NUC
{
  inventory,
  lib,
  modulesPath,
  ...
}: let
  inherit (inventory) fplnet vieta;
  host = fplnet.routers.gw1-aah1;
  services = fplnet.siteServices;
  pairs = address: ports: map (port: "${address} . ${toString port}") ports;
  siteServices = lib.concatLists (lib.mapAttrsToList (_: s: pairs s.address (s.tcp or [])) services);
  siteUdp = lib.concatLists (lib.mapAttrsToList (_: s: pairs s.address (s.udp or [])) services);
  set = lib.concatStringsSep ", ";
  proxyPorts = lib.mapAttrsToList (_: s: "${s.address} . ${toString s.proxyPort}") (lib.filterAttrs (_: s: s ? proxyPort) services);
in {
  imports = [
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
    ./bgp.nix
    ./backbone.nix
    ../../modules/base.nix
  ];

  proxmoxLXC = {
    manageNetwork = true;
    manageHostName = true;
  };

  networking = {
    hostName = "gw1-aah1";
    useHostResolvConf = false;

    # Inbound to Athena: replies, ICMPv6 and the site services. SSH from the LAN only.
    firewall = {
      allowedTCPPorts = lib.mkForce [];
      interfaces.${host.uplink.interface}.allowedTCPPorts = [22];
      filterForward = true;
      extraForwardRules =
        ''
          iifname "${host.uplink.interface}" oifname "wg-er1-*" ip6 saddr { ${vieta.nodeNetwork}, ${vieta.podNetwork} } accept
        ''
        + lib.optionalString (siteServices != []) ''
          iifname "wg-er1-*" oifname "${host.uplink.interface}" ip6 daddr . tcp dport { ${lib.concatStringsSep ", " siteServices} } accept
        ''
        + lib.optionalString (proxyPorts != []) ''
          iifname "wg-er1-*" oifname "${host.uplink.interface}" ip6 saddr ${fplnet.prefixes.edges} ip6 daddr . tcp dport { ${lib.concatStringsSep ", " proxyPorts} } accept
        ''
        + lib.optionalString (siteUdp != []) ''
          iifname "wg-er1-*" oifname "${host.uplink.interface}" ip6 daddr . udp dport { ${set siteUdp} } accept
        '';
    };

    # Tunnel MTU 1420 minus 60 bytes of IPv6 and TCP headers.
    nftables.tables.mss-clamp = {
      family = "ip6";
      content = ''
        chain forward {
          type filter hook forward priority mangle; policy accept;
          iifname "wg-er1-*" tcp flags syn / syn,rst tcp option maxseg size > 1360 tcp option maxseg size set 1360
          oifname "wg-er1-*" tcp flags syn / syn,rst tcp option maxseg size > 1360 tcp option maxseg size set 1360
        }
      '';
    };
  };

  services.openssh.startWhenNeeded = false;

  # The cluster sits on the LAN side.
  fplnet.monitoring.extraInterfaces = [host.uplink.interface];

  zramSwap.enable = lib.mkForce false;

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = host.uplink.mac;
    address = [
      host.uplink.v4
      host.uplink.v6
    ];
    routes = [{Gateway = vieta.lan.gateway;}];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
