# Vieta's FPLNET gateway: unprivileged LXC on the NUC
{
  lib,
  modulesPath,
  ...
}: {
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

    # Inbound to Athena: replies and ICMPv6 only. SSH from the LAN only.
    firewall = {
      allowedTCPPorts = lib.mkForce [];
      interfaces.eth0.allowedTCPPorts = [22];
      filterForward = true;
      extraForwardRules = ''
        iifname "eth0" oifname "wg-er1-*" ip6 saddr 2a0c:b641:f94:20::/64 accept
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

  zramSwap.enable = lib.mkForce false;

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:00:00:95";
    address = [
      "10.10.1.95/24"
      "2a0c:b641:f94:20::1/64"
    ];
    routes = [{Gateway = "10.10.1.1";}];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
