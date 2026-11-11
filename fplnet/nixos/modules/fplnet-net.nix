# fplnet.net on every edge: nginx terminates TLS behind HAProxy (haproxy.nix) with a Let's Encrypt cert from DNS-01.
# CI writes the Cloudflare token
{config, ...}: {
  networking.firewall = {
    allowedTCPPorts = [80];
    # HTTP/3 reaches nginx directl
    allowedUDPPorts = [443];
  };

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

  # CI writes the ECH key before the first switch, when the nginx group does not exist yet.
  system.activationScripts.fplnet-ech = {
    deps = ["users"];
    text = ''
      f=/var/lib/fplnet-ech/fplnet.net.pem
      [ -e "$f" ] && chgrp ${config.services.nginx.group} "$f" && chmod 640 "$f"
    '';
  };

  services.nginx = {
    enable = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;
    sslProtocols = "TLSv1.3";
    sslCiphers = null;
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
        listen 0.0.0.0:443 quic reuseport;
        listen [::]:443 quic reuseport;

        # Written by CI from kv/fplnet/ech
        ssl_ech_file /var/lib/fplnet-ech/fplnet.net.pem;

        set_real_ip_from 127.0.0.1;
        real_ip_header proxy_protocol;
        access_log off;
        add_header Alt-Svc 'h3=":443"; ma=86400' always;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
        add_header Content-Security-Policy "default-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy no-referrer always;
        add_header Cross-Origin-Opener-Policy same-origin always;
      '';
      locations = {
        "/".extraConfig = ''
          expires 5m;
        '';
        "= /healthz".extraConfig = ''
          default_type text/plain;
          expires -1;
          return 200 "ok\n";
        '';
        "= /geofeed.csv".extraConfig = ''
          types { }
          default_type "text/csv; charset=utf-8";
          expires 1h;
        '';
      };
    };
  };
}
