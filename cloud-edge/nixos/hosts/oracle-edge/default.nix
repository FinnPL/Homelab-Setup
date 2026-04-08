{ pkgs, inputs, ... }:

{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./ssh-keys.nix
    ./tailscale.nix
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
      ];
      # Tailscale interface is trusted, allow all traffic through the mesh
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  systemd.network = {
    enable = true;
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
