# Root login: Vault-signed certificates, or only hardware security keys (trustVaultCA = false).
# PK of the Vault ssh-client-signer user CA (same file as fplnet/nixos/modules).
# Refresh with: curl -sf https://vault.cloud.lippok.dev/v1/ssh-client-signer/public_key
{
  config,
  lib,
  ...
}: let
  cfg = config.minerva.ssh;
in {
  options.minerva.ssh = {
    trustVaultCA = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Accept root certificates signed by the Vault user CA.";
    };
    adminKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "FIDO2 keys (sk-ssh-ed25519, created with -O verify-required) allowed to log in as root.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.trustVaultCA || cfg.adminKeys != [];
        message = "minerva.ssh: Vault CA off and no adminKeys, nobody could log in";
      }
      {
        assertion = lib.all (lib.hasPrefix "sk-ssh-ed25519@openssh.com ") cfg.adminKeys;
        message = "minerva.ssh.adminKeys: only hardware security keys (sk-ssh-ed25519)";
      }
    ];

    environment.etc."ssh/vault_user_ca.pub" = lib.mkIf cfg.trustVaultCA {source = ./vault_user_ca.pub;};

    users.users.root.openssh.authorizedKeys.keys = cfg.adminKeys;

    services.openssh.settings = lib.mkMerge [
      {
        # Signed by hand or by the converge job; sshd starts without it.
        HostCertificate = "/etc/ssh/ssh_host_ed25519_key-cert.pub";
      }
      (lib.mkIf cfg.trustVaultCA {TrustedUserCAKeys = "/etc/ssh/vault_user_ca.pub";})
      # PIN and touch on every login
      (lib.mkIf (!cfg.trustVaultCA) {
        PubkeyAuthOptions = "verify-required";
        PubkeyAcceptedAlgorithms = "sk-ssh-ed25519@openssh.com";
        KbdInteractiveAuthentication = false;
      })
    ];
  };
}
