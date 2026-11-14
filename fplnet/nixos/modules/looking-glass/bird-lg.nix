# bird-lg-go whose frontend menu offers only the queries nginx passes (looking-glass.nix).
{
  bird-lg,
  symlinkJoin,
}: let
  frontend = bird-lg.passthru.bird-lg-frontend.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        sed -i -E '/^[[:space:]]*"(route_from_|route_filtered_|route_where|route_generic|generic)/d' frontend/render.go
        if grep -qE '"(route_where|generic)"' frontend/render.go || ! grep -q '"route_bgpmap"' frontend/render.go; then
          echo "render.go menu patch no longer matches upstream" >&2
          exit 1
        fi
      '';
  });
in
  symlinkJoin {
    pname = "bird-lg";
    inherit (bird-lg) version meta;
    paths = [frontend bird-lg.passthru.bird-lg-proxy];
  }
