{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.wireguard-tools ];

  # CI writes WG private key to /etc/wireguard/private.key
  # CI writes LXC peer pubkey to /etc/wireguard/peer-pubkey
  # CI then runs: systemctl restart clustermesh-wg
  systemd.services.clustermesh-wg = {
    description = "WireGuard tunnel for clustermesh";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.iproute2}/bin/ip link del wg0";
    };
    path = [ pkgs.wireguard-tools pkgs.iproute2 pkgs.gnugrep ];
    unitConfig = {
      ConditionPathExists = [ "/etc/wireguard/private.key" "/etc/wireguard/peer-pubkey" ];
    };
    script = ''
      set -e

      PEER_PUBKEY=$(cat /etc/wireguard/peer-pubkey | tr -d '[:space:]')

      # Create WG interface (idempotent)
      ip link del wg0 2>/dev/null || true
      ip link add wg0 type wireguard
      wg set wg0 \
        listen-port 51820 \
        private-key /etc/wireguard/private.key \
        peer "$PEER_PUBKEY" allowed-ips 10.10.1.0/24
      ip link set wg0 mtu 1420 up

      # Get this node's VCN IP (the address Cilium uses as InternalIP)
      VCN_IP=$(ip -4 addr show eth0 | grep -oP 'inet \K[0-9.]+')
      if [ -z "$VCN_IP" ]; then
        echo "Could not determine VCN IP from eth0, aborting"
        exit 1
      fi

      # Route homelab traffic through WG tunnel with correct source IP.
      # This ensures VXLAN outer headers carry the VCN IP, not the wg0 IP.
      ip route replace 10.10.1.0/24 dev wg0 table 51 src "$VCN_IP"
      if ! ip rule show | grep -q "5260:"; then
        ip rule add to 10.10.1.0/24 lookup 51 priority 5260
      fi

      echo "Clustermesh WG tunnel up: 10.10.1.0/24 via wg0 src $VCN_IP"
    '';
  };

  # On boot, start the WG service if key files already exist (persisted from prior CI deploy).
  systemd.paths.clustermesh-wg = {
    description = "Start clustermesh WG tunnel when key files exist";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      # Triggers when the file exists at boot or appears later.
      PathExists = "/etc/wireguard/private.key";
    };
  };

  # WireGuard listen port
  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Trust the WG interface for forwarded traffic
  networking.firewall.trustedInterfaces = [ "wg0" ];

  # Ensure the key directory exists
  systemd.tmpfiles.rules = [
    "d /etc/wireguard 0700 root root -"
  ];
}
