# HAProxy on :443 on every edge and routes by SNI without decrypting
{config, ...}: {
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
        tcp-request inspect-delay 5s
        tcp-request content reject unless { req.ssl_hello_type 1 }

        # No default_backend: any other name is closed.
        use_backend nginx if { req.ssl_sni -i fplnet.net }

      backend nginx
        server nginx 127.0.0.1:8443 send-proxy-v2 check inter 10s
    '';
  };
}
