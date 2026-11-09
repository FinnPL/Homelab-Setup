{
  # InterIX Amsterdam peering LAN vNIC
  systemd.network.links."10-interix" = {
    matchConfig.MACAddress = "02:00:00:1a:3a:c1";
    linkConfig.Name = "interix";
  };

  systemd.network.networks."30-interix" = {
    matchConfig.Name = "interix";
    address = [
      "185.1.185.17/23"
      "2001:7f8:134::10e/48"
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.interix.arp_ignore" = 1;
    "net.ipv4.conf.interix.arp_announce" = 2;
  };
}
