{pkgs, ...}: {
  environment.systemPackages = [pkgs.rsync];

  systemd.tmpfiles.rules = [
    "d /var/www/lippok.dev 0755 root root -"
  ];

  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    serverTokens = false;

    virtualHosts."lippok.dev" = {
      default = true;
      listen = [
        {
          addr = "127.0.0.1";
          port = 8080;
        }
      ];
      root = "/var/www/lippok.dev";
      # HAProxy already logs every request.
      extraConfig = ''
        access_log off;
        absolute_redirect off;
      '';

      locations = {
        "= /index".return = "301 /$is_args$args";
        "= /index.html".return = "301 /$is_args$args";
        "~ ^(?<page>/.+)\\.html$".return = "301 $page$is_args$args";
        "~ ^(?<page>/.+)/$".return = "301 $page$is_args$args";
        "= /" = {
          tryFiles = "/index.html =404";
          extraConfig = ''
            add_header Cache-Control "public, max-age=300";
          '';
        };
        "/" = {
          tryFiles = "$uri $uri.html =404";
          extraConfig = ''
            add_header Cache-Control "public, max-age=300";
          '';
        };
        "/_astro/".extraConfig = ''
          add_header Cache-Control "public, max-age=31536000, immutable";
        '';
        "= /status.json" = {
          alias = "/var/lib/homepage-status/status.json";
          extraConfig = ''
            add_header Cache-Control "no-store" always;
          '';
        };
      };
    };
  };

  users.users.homepage-status = {
    isSystemUser = true;
    group = "homepage-status";
  };
  users.groups.homepage-status = {};

  systemd.services.homepage-status = {
    description = "Write the homepage status.json from Gatus";
    after = ["network-online.target" "tailscaled.service"];
    wants = ["network-online.target"];
    environment.GATUS_URL = "https://status.lippok.dev";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.nodejs}/bin/node ${./homepage-status.mjs}";
      User = "homepage-status";
      Group = "homepage-status";
      # nginx reads status.json from here.
      StateDirectory = "homepage-status";
      StateDirectoryMode = "0755";
      UMask = "0022";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
    };
  };

  systemd.timers.homepage-status = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*:0/5";
      AccuracySec = "1s";
    };
  };
}
