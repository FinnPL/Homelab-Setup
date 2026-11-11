{
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
    ../../modules/haproxy.nix
    ../../modules/fplnet-net.nix
    ../../modules/anycast.nix
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
      "209.250.233.8/23"
      "2a05:f480:1800:28:5400:7ff:fe06:3983/64"
    ];
    routes = [
      {Gateway = "209.250.232.1";}
      # Source from the loopback so traceroute shows er1.fra1.fplnet.net.
      {
        Gateway = "fe80::fc00:7ff:fe06:3983";
        PreferredSource = "2a0c:b641:f9a::1";
      }
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
