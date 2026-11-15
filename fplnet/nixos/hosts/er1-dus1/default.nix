{inventory, ...}: let
  host = inventory.fplnet.routers.er1-dus1;
in {
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./bgp.nix
    ./route64.nix
    ./locix.nix
    ./backbone.nix
    ../../modules/base.nix
    ../../modules/rpki.nix
    ../../modules/bgp-filters.nix
    ../../modules/kernel-routing.nix
    ../../modules/anti-spoofing.nix
    ../../modules/haproxy.nix
    ../../modules/fplnet-net.nix
    ../../modules/lippok-dev.nix
    ../../modules/anycast.nix
    ../../modules/live.nix
    ../../modules/looking-glass.nix
  ];

  boot.loader.grub.enable = true;

  networking.hostName = "er1-dus1";

  fplnet.rpki.validator = true;

  systemd.network.networks."10-uplink" = {
    matchConfig.Name = host.uplink.interface;
    address = [
      host.uplink.v4
      host.uplink.v6
    ];
    routes = [
      {Gateway = "194.28.99.190";}
      # Source from the loopback so traceroute shows er1.dus1.fplnet.net.
      {
        Gateway = "2a0c:b640:11::ffff";
        PreferredSource = host.loopback;
      }
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
