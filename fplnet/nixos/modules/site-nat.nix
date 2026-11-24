# A host's UDP service via IPv4: Tayga writes the client's IPv4 address to 64 siit
{
  config,
  inventory,
  lib,
  ...
}: let
  host = inventory.fplnet.routers.${config.networking.hostName};
  uplink = host.uplink.interface;
  edgeV4 = inventory.address host.uplink.v4;
  tun = "siit";
  internal = "192.168.255.0/24";
  services = map (s: s // {internal = "192.168.255.${lib.last (lib.splitString "." s.lanIpv4)}";}) inventory.hostServicesV4;
  pairs = lib.concatMap (s: map (port: "${s.internal} . ${toString port}") s.udp) services;
  dnat = lib.concatMapStrings (s:
    lib.concatMapStrings (port: ''
      iifname "${uplink}" ip saddr != ${internal} ip daddr ${edgeV4} udp dport ${toString port} dnat to ${s.internal}
    '')
    s.udp)
  services;
  siit = lib.splitString "/" host.siit;
in
  lib.mkIf (pairs != []) {
    boot.kernel.sysctl."net.ipv4.conf.all.forwarding" = 1;

    services.tayga = {
      enable = true;
      tunDevice = tun;
      ipv4 = {
        address = "192.168.255.2";
        router.address = "192.168.255.1";
        pool = {
          address = "192.168.255.128";
          prefixLength = 25;
        };
      };
      ipv6 = {
        router.address = "${lib.head siit}1";
        pool = {
          address = lib.head siit;
          prefixLength = lib.toInt (lib.last siit);
        };
      };
      mappings = lib.listToAttrs (map (s: lib.nameValuePair s.internal s.address) services);
    };
    networking.interfaces.${tun}.ipv4.routes =
      map (s: {
        address = s.internal;
        prefixLength = 32;
      })
      services;

    networking.nftables.tables.site-nat = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ${dnat}
        }

        # IPv4 is forwarded for nothing else.
        chain forward {
          type filter hook forward priority filter; policy drop;
          iifname "${uplink}" oifname "${tun}" ct status dnat ip daddr . udp dport { ${lib.concatStringsSep ", " pairs} } accept
          iifname "${tun}" oifname "${uplink}" ct status dnat ct direction reply accept
        }
      '';
    };
  }
