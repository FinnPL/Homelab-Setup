# Live state of this edge for the web pages:
# round trips and loss to every pinged target, traffic per interface, and BGP sessions.
{
  config,
  lib,
  pkgs,
  ...
}: let
  dir = "/run/fplnet-live";
  loopback = lib.removeSuffix "/128" (lib.head config.systemd.network.networks."05-lo".address);
  live = pkgs.writers.writePython3Bin "fplnet-live" {flakeIgnore = ["E501"];} (builtins.readFile ./live/live.py);
in {
  systemd.services.fplnet-live = {
    description = "Live state for /live.json";
    wantedBy = ["multi-user.target"];
    after = ["prometheus-smokeping-exporter.service" "prometheus-bird-exporter.service"];
    environment = {
      LIVE_LOOPBACK = loopback;
      LIVE_OUT = "${dir}/live.json";
      LIVE_EDGE = config.networking.hostName;
    };
    serviceConfig = {
      ExecStart = "${live}/bin/fplnet-live";
      DynamicUser = true;
      RuntimeDirectory = "fplnet-live";
      RuntimeDirectoryMode = "0755";
      Restart = "always";
      RestartSec = 5;
      CapabilityBoundingSet = "";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = ["AF_INET6"];
      IPAddressAllow = [loopback];
      IPAddressDeny = "any";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = ["@system-service" "~@privileged @resources"];
      MemoryMax = "64M";
    };
  };

  services.nginx.virtualHosts."fplnet.net".locations."= /live.json".extraConfig = ''
    alias ${dir}/live.json;
    default_type application/json;
    expires -1;
  '';
}
