# Backbone links to er1-dus1, er1-ams1 and gw1-aah1.
{inventory, ...}: let
  inherit (inventory) address;
  inherit (inventory.fplnet) routers links;

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

  dus1Link = links."er1-dus1/er1-fra1";
  ams1Link = links."er1-ams1/er1-fra1";
  gw1Link = links."er1-fra1/gw1-aah1";

  dus1 = tunnel {
    name = "wg-er1-dus1";
    inherit (dus1Link) port;
    publicKey = routers.er1-dus1.wireguard;
    endpoint = "${address routers.er1-dus1.uplink.v4}:${toString dus1Link.port}";
    address = "${dus1Link.addresses.er1-fra1}/127";
  };

  ams1 = tunnel {
    name = "wg-er1-ams1";
    inherit (ams1Link) port;
    publicKey = routers.er1-ams1.wireguard;
    endpoint = "${address routers.er1-ams1.uplink.v4}:${toString ams1Link.port}";
    address = "${ams1Link.addresses.er1-fra1}/127";
  };

  # gw1-aah1 sits behind the RWTH firewall and dials in.
  gw1 = tunnel {
    name = "wg-gw1-aah1";
    inherit (gw1Link) port;
    publicKey = routers.gw1-aah1.wireguard;
    address = "${gw1Link.addresses.er1-fra1}/127";
  };
in {
  networking.firewall.allowedUDPPorts = [gw1Link.port dus1Link.port ams1Link.port];

  systemd.network = {
    netdevs = dus1.netdevs // ams1.netdevs // gw1.netdevs;
    networks = dus1.networks // ams1.networks // gw1.networks;
  };
}
