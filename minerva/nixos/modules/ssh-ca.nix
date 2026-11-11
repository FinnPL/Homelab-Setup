# PK of the Vault ssh-client-signer user CA (same file as fplnet/nixos/modules).
# Refresh with: curl -sf https://vault.cloud.lippok.dev/v1/ssh-client-signer/public_key
{
  environment.etc."ssh/vault_user_ca.pub".source = ./vault_user_ca.pub;

  services.openssh.settings = {
    TrustedUserCAKeys = "/etc/ssh/vault_user_ca.pub";

    # Signed by hand or by the converge job; sshd starts without it.
    HostCertificate = "/etc/ssh/ssh_host_ed25519_key-cert.pub";
  };
}
