{ ... }:

# Egress firewall for the MyIP container's bridge (10.88.0.0/24).
{
  networking.nftables.tables.container-egress = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter - 1;

        # Allow established/return traffic so reply packets aren't dropped by these rules in the reverse direction.
        ct state { established, related } accept

        # Block container access to OCI instance metadata.
        ip saddr 10.88.0.0/24 ip daddr 169.254.0.0/16 drop

        # Block container access to homelab/private networks.
        ip saddr 10.88.0.0/24 ip daddr 10.0.0.0/8 drop
        ip saddr 10.88.0.0/24 ip daddr 172.16.0.0/12 drop
        ip saddr 10.88.0.0/24 ip daddr 192.168.0.0/16 drop
        ip saddr 10.88.0.0/24 ip daddr 100.64.0.0/10 drop
      }
    '';
  };
}
