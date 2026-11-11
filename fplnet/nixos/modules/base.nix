# Common to every FPLNET router.
{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./ssh-ca.nix
    ./monitoring.nix
  ];

  networking = {
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
      # Answer UDP traceroute so it ends at the router instead of in stars.
      extraInputRules = ''
        udp dport 33434-33534 reject
      '';
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
  };

  systemd.tmpfiles.rules = ["d /var/lib/wireguard 0750 root systemd-network -"];

  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

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
    wireguard-tools
  ];
}
