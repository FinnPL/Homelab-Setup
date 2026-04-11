{ pkgs, inputs, ... }:

{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./ssh-keys.nix
    ./tailscale.nix
    ./wireguard.nix
    ./k3s.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_unprivileged_port_start" = 80;
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
        22    # SSH
        80    # HTTP (ACME challenges)
        443   # HTTPS
        4240  # Cilium health checks
      ];
      allowedUDPPorts = [
        41641 # Tailscale WireGuard
        8472  # Cilium VXLAN overlay
      ];
      # Tailscale and Cilium interfaces trusted.
      trustedInterfaces = [
        "tailscale0"
        "cilium_host"
        "cilium_net"
        "cilium_vxlan"
      ];
      extraInputRules = ''
        iifname "lxc*" accept
      '';
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
