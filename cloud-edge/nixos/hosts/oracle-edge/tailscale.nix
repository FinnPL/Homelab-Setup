{ pkgs, ... }:

{
  services.tailscale = {
    enable = true;
    # CI writes the OAuth client secret (tskey-client-...) to this file.
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--accept-routes"
      "--advertise-tags=tag:k8s"
    ];
  };

  # CI writes subnet CIDR  /etc/tailscale/subnet-cidr
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

  # Ensure the auth key directory exists
  systemd.tmpfiles.rules = [
    "d /etc/tailscale 0700 root root -"
  ];
}
