# Vieta's FPLNET gateway: unprivileged LXC on the NUC
{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
    ./bgp.nix
    ../../modules/base.nix
  ];

  proxmoxLXC = {
    manageNetwork = true;
    manageHostName = true;
  };

  networking = {
    hostName = "gw1-aah1";
    useHostResolvConf = false;
  };

  services.openssh.startWhenNeeded = false;

  zramSwap.enable = lib.mkForce false;

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:00:00:95";
    address = ["10.10.1.95/24"];
    routes = [{Gateway = "10.10.1.1";}];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };
}
