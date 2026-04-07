{ pkgs, inputs, ... }:

{
  imports = [
    ./disk-config.nix
    ./hardware.nix
    ./ssh-keys.nix
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  networking = {
    hostName = "oracle-edge";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22   # SSH
        80   # HTTP (ACME challenges)
        443  # HTTPS
      ];
      allowedUDPPorts = [
        41641 # Tailscale WireGuard
      ];
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

  # services.tailscale.enable = true;

  # services.k3s = {
  #   enable = true;
  #   role = "server";
  #   extraFlags = [
  #     "--flannel-backend=none"       # Cilium replaces Flannel
  #     "--disable-network-policy"     # Cilium handles policies
  #     "--disable=traefik"            # Gateway API replaces Traefik
  #     "--disable=servicelb"          # Cilium handles LB
  #   ];
  # };
}
