# Backbone links to er1-dus1, er1-ams1 and gw1-aah1.
let
  tunnel = {
    name,
    port,
    publicKey,
    endpoint ? null,
    address,
  }: {
    netdevs."40-${name}" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = name;
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = port;
      };
      wireguardPeers = [
        ({
            PublicKey = publicKey;
            AllowedIPs = ["::/0"];
          }
          // (
            if endpoint == null
            then {}
            else {
              Endpoint = endpoint;
              PersistentKeepalive = 25;
            }
          ))
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
    port = 51823;
    publicKey = "iLTzJJz4odvQm1RKR4Eui/N/KfM5VwfNkWoQFsFzCSM=";
    endpoint = "194.28.99.178:51823";
    address = "2a0c:b641:f98:1002::1/127";
  };

  ams1 = tunnel {
    name = "wg-er1-ams1";
    port = 51824;
    publicKey = "YLDF1BARenJHs6sMK9RYwmnxd/ICcnurOWpTy/iWJ1g=";
    endpoint = "188.65.164.27:51824";
    address = "2a0c:b641:f99:1001::1/127";
  };

  # gw1-aah1 sits behind the RWTH firewall and dials in.
  gw1 = tunnel {
    name = "wg-gw1-aah1";
    port = 51822;
    publicKey = "EZ2RLjPKIuKx138thvqVtSfMLrzW6ZycS1/bypmmK2k=";
    address = "2a0c:b641:f9a:1000::/127";
  };
in {
  networking.firewall.allowedUDPPorts = [51822 51823 51824];

  systemd.network = {
    netdevs = dus1.netdevs // ams1.netdevs // gw1.netdevs;
    networks = dus1.networks // ams1.networks // gw1.networks;
  };
}
