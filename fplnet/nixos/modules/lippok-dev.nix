# lippok.dev on every edge, behind Cloudflare (proxied, Full strict)
{
  config,
  pkgs,
  ...
}: let
  dir = "/var/lib/lippok-dev";
  inherit (config.services.nginx) group;
in {
  fplnet.haproxy.names = ["lippok.dev"];

  # CI copies the site with rsync over SSH.
  environment.systemPackages = [pkgs.rsync];

  systemd.tmpfiles.rules = [
    "d ${dir} 0755 root root -"
    "d ${dir}/releases 0755 root root -"
  ];

  # CI writes the key before the first switch, when the nginx group may not exist yet.
  system.activationScripts.lippok-dev-tls = {
    deps = ["users"];
    text = ''
      f=${dir}/tls/origin.key
      [ -e "$f" ] && chgrp ${group} "$f" && chmod 640 "$f"
    '';
  };

  services.nginx.virtualHosts."lippok.dev" = {
    onlySSL = true;
    sslCertificate = "${dir}/tls/origin.pem";
    sslCertificateKey = "${dir}/tls/origin.key";
    listen = [
      {
        addr = "127.0.0.1";
        port = 8443;
        ssl = true;
        proxyProtocol = true;
      }
    ];
    root = "${dir}/current";
    extraConfig = ''
      access_log off;
      absolute_redirect off;
      add_header Content-Security-Policy "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self'; connect-src 'self' https://*.fplnet.net https://site-data.relay.lippok.dev; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" always;
      add_header Referrer-Policy strict-origin-when-cross-origin always;
      add_header Cross-Origin-Opener-Policy same-origin always;
    '';
    locations = {
      "= /index".return = "301 /$is_args$args";
      "= /index.html".return = "301 /$is_args$args";
      "~ ^(?<page>/[^\\r\\n]+)\\.html$".return = "301 $page$is_args$args";
      "~ ^(?<page>/[^\\r\\n]+)/$".return = "301 $page$is_args$args";
      "= /" = {
        tryFiles = "/index.html =404";
        extraConfig = "expires 5m;";
      };
      "/" = {
        tryFiles = "$uri $uri.html =404";
        extraConfig = "expires 5m;";
      };
      "/_astro/".extraConfig = "expires max;";
      "= /lippok-dns.mobileconfig".extraConfig = ''
        types { }
        default_type application/x-apple-aspen-config;
        expires 5m;
      '';
    };
  };
}
