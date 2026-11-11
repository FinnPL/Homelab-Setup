# f91 edge anycast: every edge serves 2a0c:b641:f91::80 and announces f91::/48 only while
# fplnet.net answers there with a valid cert. The check writes the announcement into a file
# BIRD includes, so a BIRD reload or restart keeps the last verdict and a reboot starts withdrawn.
{
  config,
  lib,
  pkgs,
  ...
}: let
  address = "2a0c:b641:f91::80";
  prefix = "2a0c:b641:f91::/48";
  dir = "/run/fplnet-anycast";
  state = "${dir}/f91.conf";

  announce = pkgs.writeText "anycast-f91.conf" ''
    protocol static anycast_f91 {
      ipv6;
      route ${prefix} unreachable;
    }
  '';

  check = pkgs.writeShellApplication {
    name = "anycast-f91";
    runtimeInputs = [pkgs.coreutils pkgs.curl pkgs.gnugrep config.services.bird.package];
    text = ''
      publish() {
        install -m 644 "$1" "${state}.new"
        mv -f "${state}.new" "${state}"
        echo "$2"
        local out
        out=$(birdc configure 2>&1 || true)
        # "Reconfigured" or "Reconfiguration in progress"
        grep -q '^Reconfigur' <<< "$out" || echo "birdc configure failed, BIRD reads the verdict when it starts: $out"
      }

      up=0
      [ -s "${state}" ] && up=1
      passes=0
      fails=0
      while :; do
        if curl -fs -o /dev/null --max-time 3 --resolve "fplnet.net:443:[${address}]" https://fplnet.net/healthz; then
          passes=$((passes + 1))
          fails=0
        else
          fails=$((fails + 1))
          passes=0
        fi

        if [ "$up" = 0 ] && [ "$passes" -ge 3 ]; then
          publish ${announce} "fplnet.net answers on ${address}, announcing ${prefix}"
          up=1
        elif [ "$up" = 1 ] && [ "$fails" -ge 3 ]; then
          publish /dev/null "fplnet.net failed 3 checks on ${address}, withdrawing ${prefix}"
          up=0
        fi
        sleep 5
      done
    '';
  };
in {
  systemd.network.networks."05-lo" = {
    address = lib.mkAfter ["${address}/128"];
    routes = lib.mkAfter [
      {
        Destination = prefix;
        Type = "unreachable";
      }
    ];
  };

  users.users.fplnet-anycast = {
    isSystemUser = true;
    group = "fplnet-anycast";
    extraGroups = ["bird"];
  };
  users.groups.fplnet-anycast = {};

  system.activationScripts.fplnet-anycast = {
    deps = ["users"];
    text = ''
      install -d -m 755 -o fplnet-anycast -g fplnet-anycast ${dir}
      [ -e ${state} ] || install -m 644 -o fplnet-anycast -g fplnet-anycast /dev/null ${state}
    '';
  };

  services.bird = {
    config = lib.mkOrder 1600 ''
      # anycast_f91 exists while anycast-f91.service finds fplnet.net healthy.
      include "anycast-f91.conf";
    '';
    preCheckConfig = ''
      cp ${announce} anycast-f91.conf
    '';
  };

  environment.etc."bird/anycast-f91.conf".source = state;

  # No withdrawal on stop
  systemd.services.anycast-f91 = {
    description = "Announce ${prefix} while fplnet.net answers on ${address}";
    wantedBy = ["multi-user.target"];
    after = ["bird.service" "haproxy.service" "nginx.service"];
    serviceConfig = {
      ExecStart = lib.getExe check;
      User = "fplnet-anycast";
      Group = "fplnet-anycast";
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadWritePaths = [dir];
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
}
