{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./bgp.nix
    ./backbone.nix
    ../../modules/base.nix
  ];

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    efi.canTouchEfiVariables = false;
  };

  networking.hostName = "er1-ams1";

  systemd.network.networks."10-uplink" = {
    matchConfig.MACAddress = "bc:24:11:9f:03:19";
    address = [
      "188.65.164.27/24"
      "2602:fa7e:17::3f/48"
    ];
    routes = [
      {Gateway = "188.65.164.1";}
      {Gateway = "2602:fa7e:17::1";}
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
