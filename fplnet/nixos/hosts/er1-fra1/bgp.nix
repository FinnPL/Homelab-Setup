{
  services.bird = {
    enable = true;
    config = ''
      router id 209.250.233.8;

      define OWN_AS = 218255;

      protocol device {}

      protocol static loopback {
        ipv6;
        route 2a0c:b641:f90::3/128 unreachable;
      }

      protocol kernel {
        ipv6 {
          import none;
          export none;
        };
      }
    '';
  };

  systemd.network.networks."05-lo" = {
    matchConfig.Name = "lo";
    address = ["2a0c:b641:f90::3/128"];
  };
}
