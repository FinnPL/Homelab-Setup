# Backbone links to er1-dus1, er1-fra1 and gw1-aah1.
{inventory, ...}: let
  inherit (inventory) address;
  inherit (inventory.fplnet) routers links;
  dus1 = links."er1-dus1/er1-ams1";
  fra1 = links."er1-ams1/er1-fra1";
  gw1 = links."er1-ams1/gw1-aah1";
in {
  networking.firewall.allowedUDPPorts = [dus1.port gw1.port fra1.port];

  systemd.network = {
    netdevs."40-wg-er1-dus1" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg-er1-dus1";
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = dus1.port;
      };
      wireguardPeers = [
        {
          PublicKey = routers.er1-dus1.wireguard;
          AllowedIPs = ["::/0"];
          Endpoint = "${address routers.er1-dus1.uplink.v4}:${toString dus1.port}";
          PersistentKeepalive = 25;
        }
      ];
    };

    networks."40-wg-er1-dus1" = {
      matchConfig.Name = "wg-er1-dus1";
      address = ["${dus1.addresses.er1-ams1}/127"];
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
        ListenPort = gw1.port;
      };
      # gw1-aah1 sits behind the RWTH firewall and dials in.
      wireguardPeers = [
        {
          PublicKey = routers.gw1-aah1.wireguard;
          AllowedIPs = ["::/0"];
        }
      ];
    };

    networks."41-wg-gw1-aah1" = {
      matchConfig.Name = "wg-gw1-aah1";
      address = ["${gw1.addresses.er1-ams1}/127"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };

    netdevs."42-wg-er1-fra1" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = "wg-er1-fra1";
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = fra1.port;
      };
      wireguardPeers = [
        {
          PublicKey = routers.er1-fra1.wireguard;
          AllowedIPs = ["::/0"];
          Endpoint = "${address routers.er1-fra1.uplink.v4}:${toString fra1.port}";
          PersistentKeepalive = 25;
        }
      ];
    };

    networks."42-wg-er1-fra1" = {
      matchConfig.Name = "wg-er1-fra1";
      address = ["${fra1.addresses.er1-ams1}/127"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
