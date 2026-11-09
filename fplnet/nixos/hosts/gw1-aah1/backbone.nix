# Tunnels to every edge.
let
  tunnel = {
    name,
    publicKey,
    endpoint,
    address,
  }: {
    netdevs."40-${name}" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = name;
        MTUBytes = "1420";
      };
      wireguardConfig.PrivateKeyFile = "/var/lib/wireguard/backbone.key";
      wireguardPeers = [
        {
          PublicKey = publicKey;
          AllowedIPs = ["::/0"];
          Endpoint = endpoint;
          PersistentKeepalive = 25;
        }
      ];
    };

    networks."40-${name}" = {
      matchConfig.Name = name;
      address = [address];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };

  dus1 = tunnel {
    name = "wg-er1-dus1";
    publicKey = "iLTzJJz4odvQm1RKR4Eui/N/KfM5VwfNkWoQFsFzCSM=";
    endpoint = "194.28.99.178:51822";
    address = "2a0c:b641:f98:1000::1/127";
  };

  ams1 = tunnel {
    name = "wg-er1-ams1";
    publicKey = "YLDF1BARenJHs6sMK9RYwmnxd/ICcnurOWpTy/iWJ1g=";
    endpoint = "188.65.164.27:51822";
    address = "2a0c:b641:f99:1000::1/127";
  };

  fra1 = tunnel {
    name = "wg-er1-fra1";
    publicKey = "en+tsQ4OFy1jtCVxO3EY4mq1YfXqgomo/rBjf2aKHXc=";
    endpoint = "209.250.233.8:51822";
    address = "2a0c:b641:f9a:1000::1/127";
  };
in {
  systemd.network = {
    netdevs = dus1.netdevs // ams1.netdevs // fra1.netdevs;
    networks = dus1.networks // ams1.networks // fra1.networks;
  };
}
