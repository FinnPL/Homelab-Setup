{ ... }:

# Wildcard cert for *.cloud.lippok.dev via Let's Encrypt DNS-01.
# CI writes the Cloudflare API token to /etc/cloudflare/credentials.
# The LE account email comes from acme-email.nix (CI rewrites it)
{
  systemd.tmpfiles.rules = [
    "d /etc/cloudflare 0700 root root -"
  ];

  security.acme = {
    acceptTerms = true;

    certs."cloud.lippok.dev" = {
      domain = "cloud.lippok.dev";
      extraDomainNames = [ "*.cloud.lippok.dev" ];
      dnsProvider = "cloudflare";
      credentialsFile = "/etc/cloudflare/credentials";
      group = "haproxy";
      reloadServices = [ "haproxy.service" ];
    };
  };
}
