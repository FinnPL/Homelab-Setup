# Import policy for every external BGP session on the edges (MANRS, NLNOG bgpfilterguide).
{
  config,
  lib,
  ...
}: let
  # Informational large communities, set on import:
  #   218255:1:<site>      1 er1-dus1, 2 er1-ams1, 3 er1-fra1
  #   218255:2:<neighbour> 1 transit, 2 IX route server, 3 bilateral peer
  #   218255:3:<country>   ISO 3166-1 numeric of the site (276 DE, 528 NL)
  sites = {
    er1-dus1 = {
      id = 1;
      country = 276;
    };
    er1-ams1 = {
      id = 2;
      country = 528;
    };
    er1-fra1 = {
      id = 3;
      country = 276;
    };
  };
  host = config.networking.hostName;
  site = sites.${host} or (throw "bgp-filters: no large community site for ${host}");
in {
  services.bird.config = lib.mkOrder 700 ''
    define BOGON_ASNS = [
      0,                      # RFC 7607
      23456,                  # RFC 6793 AS_TRANS
      64496..64511,           # RFC 5398 documentation
      64512..65534,           # RFC 6996 private
      65535,                  # RFC 7300 last 16-bit
      65536..65551,           # RFC 5398 documentation
      65552..131071,          # IANA reserved
      4200000000..4294967294, # RFC 6996 private
      4294967295              # RFC 7300 last 32-bit
    ];

    # Special-purpose blocks inside 2000::/3; everything outside it is dropped anyway.
    define BOGONS_V6 = [
      2001:2::/48+,   # RFC 5180 benchmarking
      2001:10::/28+,  # RFC 4843 ORCHID
      2001:20::/28+,  # RFC 7343 ORCHIDv2
      2001:db8::/32+, # RFC 3849 documentation
      2002::/16+,     # RFC 7526 6to4
      3ffe::/16+,     # RFC 3701 6bone
      3fff::/20+      # RFC 9637 documentation
    ];

    function import_ok(bool allow_default) -> bool {
      if net = ::/0 then return allow_default;
      # Our own space never arrives from outside; a forged origin of AS218255 would pass ROV.
      if net ~ [ 2a0c:b641:f90::/44+ ] then return false;
      if !(net ~ [ 2000::/3{16,48} ]) then return false;
      if net ~ BOGONS_V6 then return false;
      if bgp_path ~ BOGON_ASNS then return false;
      if bgp_path.len > 64 then return false;
      if roa_check(r6, net, bgp_path.last_nonaggregated) = ROA_INVALID then return false;
      return true;
    }

    # Only our own tags carry 218255; a neighbour's are dropped first.
    function import_tag() {
      bgp_large_community.delete([(218255, *, *)]);
      bgp_large_community.add((218255, 1, ${toString site.id}));
      bgp_large_community.add((218255, 3, ${toString site.country}));
      # RFC 8326 graceful shutdown
      if (65535, 0) ~ bgp_community then bgp_local_pref = 0;
    }

    # Transit may hand us a default; peers and route servers may not.
    filter from_transit {
      if !import_ok(true) then reject;
      import_tag();
      bgp_large_community.add((218255, 2, 1));
      accept;
    }

    # Peers before transit (100); import_tag can still lower it for graceful shutdown.
    filter from_route_server {
      if !import_ok(false) then reject;
      bgp_local_pref = 150;
      import_tag();
      bgp_large_community.add((218255, 2, 2));
      accept;
    }

    filter from_peer {
      if !import_ok(false) then reject;
      bgp_local_pref = 150;
      import_tag();
      bgp_large_community.add((218255, 2, 3));
      accept;
    }
  '';
}
