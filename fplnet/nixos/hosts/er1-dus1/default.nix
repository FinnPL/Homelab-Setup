{
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
    matchConfig.Name = "ens18";
    address = [
      "194.28.99.178/27"
      "2a0c:b640:11:178::1/48"
    ];
    routes = [
      {Gateway = "194.28.99.190";}
      # Source from the loopback so traceroute shows er1.dus1.fplnet.net.
      {
        Gateway = "2a0c:b640:11::ffff";
        PreferredSource = "2a0c:b641:f98::1";
      }
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
