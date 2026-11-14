# lg.fplnet.net: bird-lg-go on every edge. Each edge's frontend asks every edge's proxy over the backbone.
# The proxies reach BIRD only through a restricted control socket.
{
  config,
  lib,
  pkgs,
  ...
}: let
  edges = {
    er1-dus1 = "2a0c:b641:f98::1";
    er1-ams1 = "2a0c:b641:f99::1";
    er1-fra1 = "2a0c:b641:f9a::1";
  };
  loopback = lib.removeSuffix "/128" (lib.head config.systemd.network.networks."05-lo".address);
  socket = "/run/bird/lg.ctl";
  proxyPort = 8000;
  frontendPort = 5000;

  edgeTunnels = lib.concatMapStringsSep ", " (name: ''"${name}"'') (
    lib.filter (lib.hasPrefix "wg-er1-")
    (lib.mapAttrsToList (_: netdev: netdev.netdevConfig.Name) config.systemd.network.netdevs)
  );

  # Proxy addresses joined by "+", as they appear in the frontend's URLs.
  servers = "[0-9a-f:+]+";

  allowed = [
    "^/summary/${servers}/?$"
    "^/detail/${servers}/[A-Za-z0-9_]*$"
    "^/(route|route_all|route_bgpmap)/${servers}/[0-9A-Fa-f:./]*$"
    "^/traceroute/${servers}/[A-Za-z0-9.:-]*$"
    "^/whois/[A-Za-z0-9.:/-]*$"
  ];

  proxyToFrontend = ''
    limit_req zone=lg burst=10 nodelay;
    proxy_pass http://127.0.0.1:${toString frontendPort};
    proxy_read_timeout 30s;
  '';
in {
  fplnet.haproxy.names = ["lg.fplnet.net"];
  security.acme.certs."fplnet.net".extraDomainNames = ["lg.fplnet.net"];

  services.bird.config = lib.mkAfter ''
    cli "${socket}" { restrict; };
  '';

  services.bird-lg = {
    package = pkgs.callPackage ./looking-glass/bird-lg.nix {};

    proxy = {
      enable = true;
      listenAddresses = "[${loopback}]:${toString proxyPort}";
      birdSocket = socket;
      allowedIPs = ["2a0c:b641:f98::/46"];
      traceroute = {
        binary = "${pkgs.traceroute}/bin/traceroute";
        flags = ["-q1" "-N32" "-w1"];
      };
      extraArgs = ["--traceroute-max-concurrent=2"];
    };

    frontend = {
      enable = true;
      listenAddresses = "127.0.0.1:${toString frontendPort}";
      servers = lib.mapAttrsToList (name: address: "${name}<${address}>") edges;
      domain = "";
      inherit proxyPort;
      whois = "bgp.tools";
      titleBrand = "FPLNET";
      navbar = {
        brand = "AS218255";
        brandURL = "https://fplnet.net/";
        allServers = "All edges";
      };
      protocolFilter = ["BGP"];
      extraArgs = ["--time-out=30" "--connection-time-out=3"];
    };
  };

  systemd.services = {
    bird-lg-proxy = {
      after = ["bird.service"];
      serviceConfig.MemoryMax = "256M";
    };
    bird-lg-frontend.serviceConfig.MemoryMax = "256M";
  };

  networking.firewall.extraInputRules = ''
    iifname { ${edgeTunnels} } ip6 saddr 2a0c:b641:f98::/46 tcp dport ${toString proxyPort} accept
  '';

  services.nginx = {
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=lg:10m rate=30r/m;
      limit_req_status 429;
    '';

    virtualHosts."lg.fplnet.net" = {
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
      extraConfig = ''
        listen 0.0.0.0:443 quic;
        listen [::]:443 quic;

        ssl_ech_file /var/lib/fplnet-ech/fplnet.net.pem;

        set_real_ip_from 127.0.0.1;
        real_ip_header proxy_protocol;
        access_log off;
        add_header Alt-Svc 'h3=":443"; ma=86400' always;
        add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;
        add_header Content-Security-Policy "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'" always;
        add_header X-Content-Type-Options nosniff always;
        add_header Referrer-Policy no-referrer always;
        add_header Cross-Origin-Opener-Policy same-origin always;
      '';
      locations =
        {
          "/".return = "404";
          "= /".extraConfig = proxyToFrontend;
          "/static/".extraConfig = ''
            proxy_pass http://127.0.0.1:${toString frontendPort};
            expires 1d;
          '';
          "= /favicon.ico".proxyPass = "http://127.0.0.1:${toString frontendPort}";
          "= /robots.txt".proxyPass = "http://127.0.0.1:${toString frontendPort}";
        }
        // lib.listToAttrs (map (re: lib.nameValuePair "~ ${re}" {extraConfig = proxyToFrontend;}) allowed);
    };
  };
}
