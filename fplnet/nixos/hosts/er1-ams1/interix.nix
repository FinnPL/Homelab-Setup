{inventory, ...}: let
  inherit (inventory.fplnet.routers.er1-ams1.interfaces) interix;
in {
  # InterIX Amsterdam peering LAN vNIC
  systemd.network.links."10-interix" = {
    matchConfig.MACAddress = "02:00:00:1a:3a:c1";
    linkConfig.Name = "interix";
  };

  systemd.network.networks."30-interix" = {
    matchConfig.Name = "interix";
    address = [
      interix.v4
      interix.v6
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.interix.arp_ignore" = 1;
    "net.ipv4.conf.interix.arp_announce" = 2;
    "net.ipv4.conf.interix.send_redirects" = 0;
    "net.ipv4.conf.interix.accept_redirects" = 0;
    "net.ipv6.conf.interix.accept_redirects" = 0;
    "net.ipv6.conf.interix.autoconf" = 0;
  };
}
