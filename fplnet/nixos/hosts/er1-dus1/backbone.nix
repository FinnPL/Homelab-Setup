{
  # Backbone links to er1-ams1 and gw1-aah1.
  networking.firewall.allowedUDPPorts = [51821 51822];

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
      address = ["2a0c:b641:f90:1000::/127"];
      networkConfig = {
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    };
  };
}
