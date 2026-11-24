# The inventory as the NixOS flakes read it (import ../../inventory).
let
  read = file: (builtins.fromJSON (builtins.readFile file)).inventory;
  inherit (read ./fplnet.json) fplnet;
  inherit (read ./vieta.json) vieta;
in
  read ./fplnet.json
  // read ./vieta.json
  // read ./minerva.json
  // {
    # Interface addresses carry their prefix length: "194.28.99.178/27" -> "194.28.99.178".
    address = cidr: builtins.head (builtins.split "/" cidr);

    # A host's site service also answers on IPv4 andevery edge translates it
    hostServicesV4 = map (name: let
      s = fplnet.siteServices.${name};
    in {
      inherit (s) address host;
      lanIpv4 = vieta.hosts.${s.host}.ipv4;
      udp = s.udp or [];
    }) (builtins.filter (name: fplnet.siteServices.${name} ? host) (builtins.attrNames fplnet.siteServices));
  }
