{ pkgs, inputs, ... }:

{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./ssh-keys.nix
    ./tailscale.nix
    ./wireguard.nix
    ./haproxy.nix
    ./acme.nix
    ./acme-email.nix
    ./myip.nix
    ./container-egress.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking = {
    hostName = "oracle-edge";
    useDHCP = false;
    useNetworkd = true;
    dhcpcd.enable = false;
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22  # SSH
        443 # HTTPS (HAProxy TLS passthrough)
      ];
      allowedUDPPorts = [
        41641 # Tailscale WireGuard
      ];
      trustedInterfaces = [
        "tailscale0"
      ];
      checkReversePath = "loose";
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-uplink" = {
      matchConfig.Name = "eth0";
      networkConfig.DHCP = "yes";
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  nix = {
    settings.experimental-features = [ "nix-command" "flakes" ];
    registry.nixpkgs.flake = inputs.nixpkgs;
  };

  time.timeZone = "Europe/Berlin";
  system.stateVersion = "24.11";

  environment.systemPackages = with pkgs; [
    vim
    curl
    htop
    git
  ];
}
