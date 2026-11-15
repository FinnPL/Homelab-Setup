# The inventory as the NixOS flakes read it (import ../../inventory).
let
  read = file: (builtins.fromJSON (builtins.readFile file)).inventory;
in
  read ./fplnet.json
  // read ./vieta.json
  // read ./minerva.json
  // {
    # Interface addresses carry their prefix length: "194.28.99.178/27" -> "194.28.99.178".
    address = cidr: builtins.head (builtins.split "/" cidr);
  }
