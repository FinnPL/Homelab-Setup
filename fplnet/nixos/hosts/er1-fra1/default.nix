{inventory, ...}: let
  host = inventory.fplnet.routers.er1-fra1;
in {
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./bgp.nix
    ./backbone.nix
    ../../modules/base.nix
    ../../modules/rpki.nix
    ../../modules/bgp-filters.nix
    ../../modules/kernel-routing.nix
    ../../modules/anti-spoofing.nix
    ../../modules/site-nat.nix
    ../../modules/haproxy.nix
    ../../modules/fplnet-net.nix
    ../../modules/lippok-dev.nix
    ../../modules/anycast.nix
    ../../modules/live.nix
    ../../modules/looking-glass.nix
  ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = false;
  };

  networking.hostName = "er1-fra1";

  systemd.network.networks."10-uplink" = {
    matchConfig.MACAddress = "56:00:07:06:39:83";
    address = [
      host.uplink.v4
      host.uplink.v6
    ];
    routes = [
      {Gateway = "209.250.232.1";}
      # Source from the loopback so traceroute shows er1.fra1.fplnet.net.
      {
        Gateway = "fe80::fc00:7ff:fe06:3983";
        PreferredSource = host.loopback;
      }
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
