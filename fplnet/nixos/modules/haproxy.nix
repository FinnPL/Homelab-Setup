# HAProxy on :443 on every edge and routes by SNI without decrypting
{
  config,
  lib,
  ...
}: let
  siteServices = lib.filterAttrs (_: s: lib.elem 443 s.tcp) (lib.importJSON ../site-services.json);

  siteRoutes = lib.concatStrings (lib.mapAttrsToList (name: _: ''
      use_backend site_${name} if { req.ssl_sni -i ${name} }
    '')
    siteServices);

  siteBackends = lib.concatStrings (lib.mapAttrsToList (name: s: ''
      backend site_${name}
        server site [${s.address}]:443 check inter 10s check-ssl check-sni ${name} verify required verifyhost ${name} ca-file /etc/ssl/certs/ca-certificates.crt
    '')
    siteServices);
in {
  options.fplnet.haproxy.names = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Server names handed to the local nginx.";
  };

  config = {
    networking.firewall.allowedTCPPorts = [443];

    systemd.services.haproxy.reloadTriggers = [config.environment.etc."haproxy.cfg".source];

    services.haproxy = {
      enable = true;
      config = ''
        global
          log /dev/log local0 info
          maxconn 4000

        defaults
          log global
          mode tcp
          option tcplog
          option dontlognull
          # Log only failed or aborted connections, not every visit and health check.
          option dontlog-normal
          timeout connect 5s
          timeout client  1m
          timeout server  1m

        frontend tls_in
          bind :::443 v4v6

          stick-table type ipv6 size 100k expire 1m store conn_rate(10s),conn_cur
          tcp-request connection track-sc0 src
          tcp-request connection reject if { sc0_conn_rate gt 100 } || { sc0_conn_cur gt 100 }

          tcp-request inspect-delay 5s
          tcp-request content reject unless { req.ssl_hello_type 1 }

          # No default_backend: any other name is closed.
          use_backend nginx if { req.ssl_sni -i ${lib.concatStringsSep " " config.fplnet.haproxy.names} }
          ${siteRoutes}

        # TLV 0xe0: the kernel's RTT to the client in microseconds, for the connection page.
        backend nginx
          server nginx 127.0.0.1:8443 send-proxy-v2 set-proxy-v2-tlv-fmt(0xe0) %[fc_rtt(us)] check inter 10s

        ${siteBackends}
      '';
    };
  };
}
