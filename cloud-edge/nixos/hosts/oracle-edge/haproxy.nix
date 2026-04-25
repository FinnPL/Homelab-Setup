{ ... }:

# Public TLS passthrough relay.
{
  services.haproxy = {
    enable = true;
    config = ''
      global
        log /dev/log local0 info
        maxconn 4000

      defaults
        mode tcp
        log global
        option tcplog
        option dontlognull
        timeout connect 5s
        timeout client  1m
        timeout server  1m
        timeout tunnel  1h

      frontend tls_passthrough
        bind :443
        tcp-request inspect-delay 5s
        tcp-request content accept if { req.ssl_hello_type 1 }

        use_backend homelab_blocky if { req.ssl_sni -i dns.relay.lippok.dev }

        # Future example:
        #   use_backend homelab_gateway if { req.ssl_sni -i app.relay.lippok.dev }
        # backend homelab_gateway
        #   server gw <cilium-ingress-lb-ip>:443 check inter 10s

        tcp-request content reject

      backend homelab_blocky
        # Reachable over wg0 thanks to the route+rule in wireguard.nix
        # and the masquerade on mesh-router (10.10.1.90).
        server blocky 10.10.1.201:443 check inter 10s
    '';
  };
}
