{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./bgp.nix
    ./route64.nix
    ./locix.nix
    ../../modules/ssh-ca.nix
  ];

  boot.loader.grub.enable = true;

  networking = {
    hostName = "er1-dus1";
    useDHCP = false;
    useNetworkd = true;
    dhcpcd.enable = false;
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
      "2606:4700:4700::1111"
    ];
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
      ];
      checkReversePath = "loose";
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-uplink" = {
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
          PreferredSource = "2a0c:b641:f90::1";
        }
      ];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "ipv6";
      };
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAzhAxEIjiH8TuO9toC0OYag/H08NGJBG92eZshgj0VD"
  ];

  zramSwap.enable = true;
  services.journald.extraConfig = "SystemMaxUse=500M";

  nix = {
    settings.experimental-features = ["nix-command" "flakes"];
    registry.nixpkgs.flake = inputs.nixpkgs;
  };

  time.timeZone = "Europe/Berlin";
  system.stateVersion = "26.05";

  environment.systemPackages = with pkgs; [
    vim
    curl
    htop
    git
    mtr
    tcpdump
  ];
}
