{ ... }:

{
  services.tailscale = {
    enable = true;
    # CI writes the OAuth client secret (tskey-client-...) to this file.
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--accept-routes"
    ];
  };

  # Ensure the auth key directory exists
  systemd.tmpfiles.rules = [
    "d /etc/tailscale 0700 root root -"
  ];
}
