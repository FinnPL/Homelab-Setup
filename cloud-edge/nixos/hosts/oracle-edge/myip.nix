{ pkgs, ... }:

{
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    autoPrune.enable = true;
  };

  virtualisation.oci-containers = {
    backend = "podman";
    containers.myip = {
      # renovate: datasource=docker depName=jason5ng32/myip
      image = "jason5ng32/myip:v6.1.0";
      autoStart = true;
      ports = [ "127.0.0.1:18966:18966" ];
      extraOptions = [
        "--network=myip-net"
        "--read-only"
        "--tmpfs=/tmp:rw,size=64m,mode=1777"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--memory=384m"
        "--memory-swap=384m"
        "--pids-limit=128"
        "--cpus=0.5"
      ];
    };
  };

  systemd.services.myip-network = {
    description = "Create dedicated podman bridge for the MyIP container";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "podman-myip.service" ];
    before = [ "podman-myip.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.podman ];
    script = ''
      podman network exists myip-net || podman network create \
        --driver bridge \
        --subnet 10.88.0.0/24 \
        --gateway 10.88.0.1 \
        myip-net
    '';
  };
}
