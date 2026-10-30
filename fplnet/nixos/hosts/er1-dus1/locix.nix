{
  # LocIX Dusseldorf peering LAN, presented by Servperso as a second vNIC.
  # LocIX only forwards frames from the registered MAC bc:24:11:67:6c:77.
  systemd.network.networks."30-locix-dus" = {
    matchConfig.Name = "ens19";
    address = [
      "185.1.155.233/24"
      "2a0c:b641:701::a5:21:8255:1/64"
    ];
    networkConfig = {
      IPv6AcceptRA = false;
      LinkLocalAddressing = "ipv6";
    };
  };

  # Answer ARP on the IX only for the IX address, never for the uplink's.
  boot.kernel.sysctl = {
    "net.ipv4.conf.ens19.arp_ignore" = 1;
    "net.ipv4.conf.ens19.arp_announce" = 2;
  };
}
