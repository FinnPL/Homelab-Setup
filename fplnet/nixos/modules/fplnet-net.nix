# fplnet.net on every edge: nginx terminates TLS behind HAProxy (haproxy.nix) with a Let's Encrypt cert from DNS-01.
# CI writes the Cloudflare token
{config, ...}: {
  networking.firewall.allowedTCPPorts = [80];

  security.acme = {
    acceptTerms = true;
    defaults.email = "certs@lippok.eu";
    certs."fplnet.net" = {
      dnsProvider = "cloudflare";
      environmentFile = "/etc/cloudflare/credentials";
      dnsResolver = "1.1.1.1:53";
      inherit (config.services.nginx) group;
      reloadServices = ["nginx.service"];
    };
  };

  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    serverTokens = false;

    virtualHosts."fplnet.net" = {
      default = true;
      useACMEHost = "fplnet.net";
      forceSSL = true;
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
        {
          addr = "127.0.0.1";
          port = 8443;
          ssl = true;
          proxyProtocol = true;
        }
      ];
      root = ../web/fplnet.net;
      extraConfig = ''
        set_real_ip_from 127.0.0.1;
        real_ip_header proxy_protocol;
        access_log off;
        add_header Cache-Control "public, max-age=300";
      '';
      locations = {
        "= /healthz".extraConfig = ''
          default_type text/plain;
          add_header Cache-Control "no-store";
          return 200 "ok\n";
        '';
        "= /geofeed.csv".extraConfig = ''
          types { }
          default_type "text/csv; charset=utf-8";
          add_header Cache-Control "public, max-age=3600";
        '';
      };
    };
  };
}
