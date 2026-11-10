# Each edge forwards along its own best BGP routes instead of the provider default.
{
  config,
  lib,
  ...
}: let
  loopback = lib.removeSuffix "/128" (lib.head config.systemd.network.networks."05-lo".address);
in {
  services.bird.config = lib.mkOrder 1500 ''
    # External bests leave from the loopback, never from an IX or uplink address.
    # ::/0 stays networkd's, so a stopped BIRD falls back to the provider.
    filter to_kernel {
      if proto ~ "ibgp_*" then accept;
      if source != RTS_BGP || net = ::/0 then reject;
      krt_prefsrc = ${loopback};
      accept;
    }

    # Metric 512 sits above connected routes (256)
    protocol kernel {
      metric 512;
      ipv6 {
        import none;
        export filter to_kernel;
      };
    }
  '';
}
