{pkgs, ...}: {
  systemd.tmpfiles.rules = [
    "d /etc/myip 0700 root root -"
    "f /etc/myip/secrets.env 0600 root root -"
  ];

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
      ports = ["127.0.0.1:18966:18966"];
      environment = {
        ALLOWED_DOMAINS = "dns-check.cloud.lippok.dev";
      };
      environmentFiles = ["/etc/myip/secrets.env"];
      extraOptions = [
        "--network=myip-net"
        "--dns=1.1.1.1"
        "--dns=1.0.0.1"
        "--read-only"
        "--tmpfs=/tmp:rw,size=256m,mode=1777"
        "--tmpfs=/app/common/maxmind-db:rw,size=256m"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--memory=768m"
        "--memory-swap=768m"
        "--pids-limit=128"
        "--cpus=0.5"
      ];
    };
  };

  systemd.services.myip-network = {
    description = "Create dedicated podman bridge for the MyIP container";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["podman-myip.service"];
    before = ["podman-myip.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.podman];
    script = ''
      podman network exists myip-net || podman network create \
        --driver bridge \
        --subnet 10.89.0.0/24 \
        --gateway 10.89.0.1 \
        --disable-dns \
        myip-net
    '';
  };
}
