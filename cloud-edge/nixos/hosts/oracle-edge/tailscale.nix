{ pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    # CI writes the OAuth client secret (tskey-client-...) to this file.
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--accept-routes"
      "--accept-dns=false"
      "--advertise-tags=tag:k8s"
    ];
  };

  # CI writes subnet CIDR to /etc/tailscale/subnet-cidr
  systemd.services.tailscale-advertise-routes = {
    description = "Advertise VCN subnet route via Tailscale";
    after = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wants = [ "tailscaled.service" "tailscaled-autoconnect.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.tailscale ];
    script = ''
      for i in $(seq 1 30); do
        if tailscale status >/dev/null 2>&1; then break; fi
        sleep 2
      done
      CIDR=$(cat /etc/tailscale/subnet-cidr 2>/dev/null || echo "")
      if [ -n "$CIDR" ]; then
        tailscale set --advertise-routes="$CIDR" --snat-subnet-routes=false
      fi
    '';
  };

  systemd.services.clustermesh-routes = {
    description = "Set VXLAN source IP for clustermesh traffic";
    after = [ "tailscaled.service" "tailscale-advertise-routes.service" ];
    wants = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = ''
      # Wait for tailscale0 to come up
      for i in $(seq 1 30); do
        if ip link show tailscale0 &>/dev/null; then break; fi
        sleep 2
      done

      # Get this node's VCN IP (the address Cilium uses as InternalIP)
      VCN_IP=$(ip -4 addr show eth0 | grep -oP 'inet \K[0-9.]+')
      if [ -z "$VCN_IP" ]; then
        echo "Could not determine VCN IP from eth0, aborting"
        exit 1
      fi

      # Table 51: routes to homelab nodes via tailscale0 with correct source
      ip route replace 10.10.1.0/24 dev tailscale0 table 51 src "$VCN_IP"

      # Rule at priority 5260: checked before Tailscale's table 52 (at 5270)
      if ! ip rule show | grep -q "5260:"; then
        ip rule add to 10.10.1.0/24 lookup 51 priority 5260
      fi

      echo "Clustermesh routes configured: 10.10.1.0/24 via tailscale0 src $VCN_IP"
    '';
  };

  # Ensure the auth key directory exists
  systemd.tmpfiles.rules = [
    "d /etc/tailscale 0700 root root -"
  ];
}
