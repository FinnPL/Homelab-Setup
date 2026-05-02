{ ... }:

#   *.relay.lippok.dev:   SNI passthrough to homelab (E2E TLS preserved)
#   *.cloud.lippok.dev:   terminate locally, host-route to a cloud-edge backend
{
  services.haproxy = {
    enable = true;
    config = ''
      global
        log /dev/log local0 info
        maxconn 4000

      defaults
        log global
        option dontlognull
        timeout connect 5s
        timeout client  1m
        timeout server  1m
        timeout tunnel  1h

      # Inspects SNI: either proxies raw TCP or hands off internally
      frontend tls_in
        bind :443
        mode tcp
        option tcplog
        tcp-request inspect-delay 5s
        tcp-request content accept if { req.ssl_hello_type 1 }

        use_backend homelab_blocky if { req.ssl_sni -i dns.relay.lippok.dev }
        use_backend local_https    if { req.ssl_sni -m end -i .cloud.lippok.dev }

        tcp-request content reject

      backend homelab_blocky
        mode tcp
        # Reachable over wg0 thanks to the route+rule in wireguard.nix
        # and the masquerade on mesh-router (10.10.1.90).
        server blocky 10.10.1.201:443 check inter 10s

      # send-proxy-v2 carries the real client IP across to the local frontend
      # so X-Forwarded-For below reflects the actual remote, not 127.0.0.1.
      backend local_https
        mode tcp
        server local 127.0.0.1:8443 send-proxy-v2

      # Local TLS-terminating frontend for *.cloud.lippok.dev. accept-proxy
      # consumes the PROXY-v2 header from local_https.
      frontend cloud_https
        bind 127.0.0.1:8443 ssl crt /var/lib/acme/cloud.lippok.dev/full.pem accept-proxy
        mode http
        option httplog
        option forwardfor
        http-request set-header X-Real-IP %[src]
        http-request set-header X-Forwarded-Proto https
        http-request set-header X-Forwarded-Port 443

        use_backend myip if { hdr(host) -i dns-check.cloud.lippok.dev }

        http-request deny status 404

      backend myip
        mode http
        server myip 127.0.0.1:18966 check inter 10s
    '';
  };
}
