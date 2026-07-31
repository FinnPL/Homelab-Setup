# PK of the Vault ssh-client-signer user CA.
# Refresh with: curl -sf https://vault.cloud.lippok.dev/v1/ssh-client-signer/public_key
# cloud-edge/compute.tf reads the same file for the pre-NixOS bootstrap image.
{
  environment.etc."ssh/vault_user_ca.pub".source = ./vault_user_ca.pub;

  services.openssh.settings = {
    TrustedUserCAKeys = "/etc/ssh/vault_user_ca.pub";

    # CI writes the file at runtime, it is absent on a fresh host.
    HostCertificate = "/etc/ssh/ssh_host_ed25519_key-cert.pub";
  };
}
