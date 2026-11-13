# Common to every Minerva NixOS host.
{
  pkgs,
  inputs,
  ...
}: {
  imports = [./ssh-ca.nix];

  networking = {
    useDHCP = false;
    useNetworkd = true;
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };
  };

  systemd.network = {
    enable = true;
    wait-online.anyInterface = true;
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  services.qemuGuest.enable = true;
  zramSwap.enable = true;
  services.journald.extraConfig = "SystemMaxUse=500M";

  nix = {
    settings.experimental-features = ["nix-command" "flakes"];
    registry.nixpkgs.flake = inputs.nixpkgs;
    gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };
  };

  time.timeZone = "Europe/Berlin";
  system.stateVersion = "26.05";

  environment.systemPackages = with pkgs; [
    vim
    curl
    htop
    tmux
    rsync
    pv
    lsscsi
    sg3_utils
    smartmontools
  ];
}
