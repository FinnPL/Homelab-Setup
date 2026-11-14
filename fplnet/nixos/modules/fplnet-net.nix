# fplnet.net on every edge: nginx terminates TLS behind HAProxy (haproxy.nix) with a Let's Encrypt cert from DNS-01.
# CI writes the Cloudflare token
{
  config,
  lib,
  ...
}: let
  names = ["v4.fplnet.net" "v6.fplnet.net" "dns-check.fplnet.net" "${lib.replaceStrings ["-"] ["."] config.networking.hostName}.fplnet.net"];
in {
  fplnet.haproxy.names = ["fplnet.net"] ++ names;

  networking.firewall = {
    allowedTCPPorts = [80];
    # HTTP/3 reaches nginx directl
    allowedUDPPorts = [443];
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "certs@lippok.eu";
    certs."fplnet.net" = {
      extraDomainNames = names;
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

    appendHttpConfig = ''
      map $remote_addr $client_ip {
        "~^::ffff:(?<v4>[0-9.]+)$" $v4;
        default $remote_addr;
      }
      map $client_ip $client_family {
        "~:" 6;
        default 4;
      }
      # lippok.dev reads /live.json from every edge
      map $http_origin $cors_origin {
        "https://fplnet.net" $http_origin;
        "https://lippok.dev" $http_origin;
        default "https://fplnet.net";
      }
    '';

    virtualHosts."fplnet.net" = {
      default = true;
      serverAliases = names;
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
        add_header Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self' https://*.fplnet.net; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy no-referrer always;
        add_header Cross-Origin-Opener-Policy same-origin always;
        add_header Access-Control-Allow-Origin $cors_origin always;
        add_header Timing-Allow-Origin $cors_origin always;
        add_header Vary Origin always;
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
        "= /connection".extraConfig = ''
          ssi on;
          expires -1;
          default_type text/html;
          try_files /connection.html =404;
        '';
        "= /connection.html".extraConfig = ''
          internal;
        '';
        "= /api/conn".extraConfig = ''
          default_type application/json;
          expires -1;
          return 200 '{"ip":"$client_ip","family":$client_family,"edge":"$hostname","protocol":"$server_protocol","tls":"$ssl_protocol","cipher":"$ssl_cipher","group":"$ssl_curve","ech":"$ssl_ech_status","alpn":"$ssl_alpn_protocol","resumed":"$ssl_session_reused","early":"$ssl_early_data","rtt_us":"$proxy_protocol_tlv_0xe0"}\n';
        '';
        "= /api/ping".extraConfig = ''
          expires -1;
          return 204;
        '';
      };
    };
  };
}
