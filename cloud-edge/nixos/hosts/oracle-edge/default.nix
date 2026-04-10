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
        32379 # Cilium Cluster Mesh (etcd) NodePort
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
