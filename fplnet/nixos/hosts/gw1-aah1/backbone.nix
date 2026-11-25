# Tunnels to every edge. A connection that came in through one leaves through it again.
{
  inventory,
  lib,
  ...
}: let
  inherit (inventory) address;
  inherit (inventory.fplnet) routers links;

  tunnel = {
    name,
    publicKey,
    endpoint,
    listenPort,
    address,
    siit,
    table,
  }: {
    inherit name table;
    netdevs."40-${name}" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = name;
        MTUBytes = "1420";
      };
      wireguardConfig = {
        PrivateKeyFile = "/var/lib/wireguard/backbone.key";
        ListenPort = listenPort;
      };
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
      # Replies to IPv4 clients this edge translated (site-nat.nix), and to connections marked as having come in here, go back through it.
      routes = [
        {Destination = siit;}
        {
          Destination = "::/0";
          Table = table;
        }
      ];
      routingPolicyRules = [
        {
          Family = "ipv6";
          FirewallMark = table;
          Table = table;
          Priority = table;
        }
      ];
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
    listenPort = dus1Link.gatewayPort;
    address = "${dus1Link.addresses.gw1-aah1}/127";
    inherit (routers.er1-dus1) siit;
    table = 1001;
  };

  ams1 = tunnel {
    name = "wg-er1-ams1";
    publicKey = routers.er1-ams1.wireguard;
    endpoint = "${address routers.er1-ams1.uplink.v4}:${toString ams1Link.port}";
    listenPort = ams1Link.gatewayPort;
    address = "${ams1Link.addresses.gw1-aah1}/127";
    inherit (routers.er1-ams1) siit;
    table = 1002;
  };

  fra1 = tunnel {
    name = "wg-er1-fra1";
    publicKey = routers.er1-fra1.wireguard;
    endpoint = "${address routers.er1-fra1.uplink.v4}:${toString fra1Link.port}";
    listenPort = fra1Link.gatewayPort;
    address = "${fra1Link.addresses.gw1-aah1}/127";
    inherit (routers.er1-fra1) siit;
    table = 1003;
  };

  tunnels = [dus1 ams1 fra1];
  marks = lib.concatMapStringsSep ", " (t: ''"${t.name}" : ${toString t.table}'') tunnels;
in {
  systemd.network = {
    netdevs = lib.mergeAttrsList (map (t: t.netdevs) tunnels);
    networks = lib.mergeAttrsList (map (t: t.networks) tunnels);
  };

  networking.nftables.tables.ingress-return = {
    family = "ip6";
    content = ''
      chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        iifname "wg-er1-*" ct state new ct mark set iifname map { ${marks} }
        iifname "${routers.gw1-aah1.uplink.interface}" ct direction reply ct mark != 0 meta mark set ct mark
      }
    '';
  };
}
