# Tunnels to every edge.
{inventory, ...}: let
  inherit (inventory) address;
  inherit (inventory.fplnet) routers links;

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

  dus1Link = links."er1-dus1/gw1-aah1";
  ams1Link = links."er1-ams1/gw1-aah1";
  fra1Link = links."er1-fra1/gw1-aah1";

  dus1 = tunnel {
    name = "wg-er1-dus1";
    publicKey = routers.er1-dus1.wireguard;
    endpoint = "${address routers.er1-dus1.uplink.v4}:${toString dus1Link.port}";
    address = "${dus1Link.addresses.gw1-aah1}/127";
  };

  ams1 = tunnel {
    name = "wg-er1-ams1";
    publicKey = routers.er1-ams1.wireguard;
    endpoint = "${address routers.er1-ams1.uplink.v4}:${toString ams1Link.port}";
    address = "${ams1Link.addresses.gw1-aah1}/127";
  };

  fra1 = tunnel {
    name = "wg-er1-fra1";
    publicKey = routers.er1-fra1.wireguard;
    endpoint = "${address routers.er1-fra1.uplink.v4}:${toString fra1Link.port}";
    address = "${fra1Link.addresses.gw1-aah1}/127";
  };
in {
  systemd.network = {
    netdevs = dus1.netdevs // ams1.netdevs // fra1.netdevs;
    networks = dus1.networks // ams1.networks // fra1.networks;
  };
}
