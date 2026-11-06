{
  # Backbone link to er1-ams1.
  networking.firewall.allowedUDPPorts = [51821];

  systemd.network = {
    netdevs."40-wg-er1-ams1" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg-er1-ams1";
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = 51821;
      };
      wireguardPeers = [
        {
          PublicKey = "YLDF1BARenJHs6sMK9RYwmnxd/ICcnurOWpTy/iWJ1g=";
          AllowedIPs = ["::/0"];
          Endpoint = "188.65.164.27:51821";
          PersistentKeepalive = 25;
        }
      ];
    };

    networks."40-wg-er1-ams1" = {
      matchConfig.Name = "wg-er1-ams1";
      address = ["2a0c:b641:f90:1001::/127"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
