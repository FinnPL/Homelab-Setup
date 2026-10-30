{
  # Route64 BGP tunnel, r4-fra-de.
  systemd.tmpfiles.rules = ["d /var/lib/wireguard 0750 root systemd-network -"];

  # r4-fra-de answers from 81.18.58.23, not the 45.153.82.87 we send to, so conntrack
  # never matches the reply. WireGuard drops unauthenticated packets itself.
  networking.firewall.allowedUDPPorts = [51820];

  systemd.network = {
    netdevs."20-wg-r64-fra4" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg-r64-fra4";
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/route64.key";
        ListenPort = 51820;
      };
      wireguardPeers = [
        {
          PublicKey = "07jHuRVxfJJAqXwhpjln74iE1GpgXbnzzGQ88OviQAg=";
          AllowedIPs = ["::/0"];
          Endpoint = "45.153.82.87:20108";
          PersistentKeepalive = 15;
        }
      ];
    };

    networks."20-wg-r64-fra4" = {
      matchConfig.Name = "wg-r64-fra4";
      address = ["2a11:6c7:f00:2b4::2/64"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
