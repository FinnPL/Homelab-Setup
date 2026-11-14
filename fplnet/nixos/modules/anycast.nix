# Anycast prefixes every edge announces while a check passes. Each check writes its announcement
# into a file BIRD includes, so a BIRD reload or restart keeps the last verdict and a reboot starts withdrawn.
#   f91 edge anycast: served on the edge, announced while fplnet.net answers on f91::80 with a valid cert.
#   f92 site anycast: served at the sites, announced while a site gateway hands this edge an f92 address over iBGP.
{
  config,
  lib,
  pkgs,
  ...
}: let
  edgeAddress = "2a0c:b641:f91::80";
  dir = "/run/fplnet-anycast";

  prefixes = {
    f91 = {
      prefix = "2a0c:b641:f91::/48";
      healthy = "fplnet.net answers on ${edgeAddress}";
      check = "curl -fs -o /dev/null --max-time 3 --resolve 'fplnet.net:443:[${edgeAddress}]' https://fplnet.net/healthz";
      after = ["haproxy.service" "nginx.service"];
    };
    f92 = {
      prefix = "2a0c:b641:f92::/48";
      healthy = "a site gateway announces an f92 address";
      check = ''[[ "$(birdc -r 'show route where net ~ [ 2a0c:b641:f92::/48{128,128} ] && proto ~ "ibgp_gw1_*"')" == *2a0c:b641:f92:* ]]'';
      after = [];
    };
  };

  state = name: "${dir}/${name}.conf";

  announce = name: p:
    pkgs.writeText "anycast-${name}.conf" ''
      protocol static anycast_${name} {
        ipv6;
        route ${p.prefix} unreachable;
      }
    '';

  checker = name: p:
    pkgs.writeShellApplication {
      name = "anycast-${name}";
      runtimeInputs = [pkgs.coreutils pkgs.curl pkgs.gnugrep config.services.bird.package];
      text = ''
        publish() {
          install -m 644 "$1" "${state name}.new"
          mv -f "${state name}.new" "${state name}"
          echo "$2"
          local out
          out=$(birdc configure 2>&1 || true)
          # "Reconfigured" or "Reconfiguration in progress"
          grep -q '^Reconfigur' <<< "$out" || echo "birdc configure failed, BIRD reads the verdict when it starts: $out"
        }

        up=0
        [ -s "${state name}" ] && up=1
        passes=0
        fails=0
        while :; do
          if ${p.check}; then
            passes=$((passes + 1))
            fails=0
          else
            fails=$((fails + 1))
            passes=0
          fi

          if [ "$up" = 0 ] && [ "$passes" -ge 3 ]; then
            publish ${announce name p} "${p.healthy}, announcing ${p.prefix}"
            up=1
          elif [ "$up" = 1 ] && [ "$fails" -ge 3 ]; then
            publish /dev/null "3 checks failed (${p.healthy}), withdrawing ${p.prefix}"
            up=0
          fi
          sleep 5
        done
      '';
    };
in {
  systemd.network.networks."05-lo" = {
    address = lib.mkAfter ["${edgeAddress}/128"];
    routes = lib.mkAfter (lib.mapAttrsToList (_: p: {
        Destination = p.prefix;
        Type = "unreachable";
      })
      prefixes);
  };

  users.users.fplnet-anycast = {
    isSystemUser = true;
    group = "fplnet-anycast";
    extraGroups = ["bird"];
  };
  users.groups.fplnet-anycast = {};

  system.activationScripts.fplnet-anycast = {
    deps = ["users"];
    text =
      ''
        install -d -m 755 -o fplnet-anycast -g fplnet-anycast ${dir}
      ''
      + lib.concatMapStrings (name: ''
        [ -e ${state name} ] || install -m 644 -o fplnet-anycast -g fplnet-anycast /dev/null ${state name}
      '') (lib.attrNames prefixes);
  };

  services.bird = {
    # anycast_<name> exists while anycast-<name>.service finds its check passing.
    config = lib.mkOrder 1600 (lib.concatMapStrings (name: ''
      include "anycast-${name}.conf";
    '') (lib.attrNames prefixes));
    preCheckConfig = lib.concatStrings (lib.mapAttrsToList (name: p: ''
        cp ${announce name p} anycast-${name}.conf
      '')
      prefixes);
  };

  environment.etc = lib.mapAttrs' (name: _: lib.nameValuePair "bird/anycast-${name}.conf" {source = state name;}) prefixes;

  # No withdrawal on stop
  systemd.services = lib.mapAttrs' (name: p:
    lib.nameValuePair "anycast-${name}" {
      description = "Announce ${p.prefix} while ${p.healthy}";
      wantedBy = ["multi-user.target"];
      after = ["bird.service"] ++ p.after;
      serviceConfig = {
        ExecStart = lib.getExe (checker name p);
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
    })
  prefixes;
}
