{
  # Backbone links to er1-dus1 and gw1-aah1.
  networking.firewall.allowedUDPPorts = [51821 51822];

  systemd.network = {
    netdevs."40-wg-er1-dus1" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg-er1-dus1";
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = 51821;
      };
      wireguardPeers = [
        {
          PublicKey = "iLTzJJz4odvQm1RKR4Eui/N/KfM5VwfNkWoQFsFzCSM=";
          AllowedIPs = ["::/0"];
          Endpoint = "194.28.99.178:51821";
          PersistentKeepalive = 25;
        }
      ];
    };

    networks."40-wg-er1-dus1" = {
      matchConfig.Name = "wg-er1-dus1";
      address = ["2a0c:b641:f90:1001::1/127"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };

    netdevs."41-wg-gw1-aah1" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg-gw1-aah1";
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = 51822;
      };
      # gw1-aah1 sits behind the RWTH firewall and dials in.
      wireguardPeers = [
        {
          PublicKey = "EZ2RLjPKIuKx138thvqVtSfMLrzW6ZycS1/bypmmK2k=";
          AllowedIPs = ["::/0"];
        }
      ];
    };

    networks."41-wg-gw1-aah1" = {
      matchConfig.Name = "wg-gw1-aah1";
      address = ["2a0c:b641:f90:1002::/127"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
