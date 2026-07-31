resource "vault_policy" "vault_deploy" {
  name = "vault-deploy"

  policy = <<-EOT
    # Auth method mounts + tuning (jwt enable, userpass lockout tune)
    path "sys/auth" { capabilities = ["read"] }
    path "sys/auth/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }

    # Secret engine mounts (kv)
    path "sys/mounts" { capabilities = ["read"] }
    path "sys/mounts/*" { capabilities = ["create", "read", "update", "delete", "sudo"] }

    # ACL policies
    path "sys/policies/acl" { capabilities = ["list"] }
    path "sys/policies/acl/*" { capabilities = ["create", "read", "update", "delete", "list"] }

    # Rate-limit quotas
    path "sys/quotas/rate-limit" { capabilities = ["list"] }
    path "sys/quotas/rate-limit/*" { capabilities = ["create", "read", "update", "delete", "list"] }

    # JWT auth backend config + roles
    path "auth/github-actions/*" { capabilities = ["create", "read", "update", "delete", "list"] }
    path "auth/vieta-cluster/*" { capabilities = ["create", "read", "update", "delete", "list"] }

    # AWS secrets engine roles (config/root is seeded out-of-band, not readable here)
    path "aws/roles/*" { capabilities = ["create", "read", "update", "delete", "list"] }

    # SSH user CA: the signing key is generated in-place and never read back
    path "ssh-client-signer/config/ca" { capabilities = ["create", "read", "update", "delete"] }
    path "ssh-client-signer/roles/*" { capabilities = ["create", "read", "update", "delete", "list"] }

    # SSH host CA: same shape as the user CA above
    path "ssh-host-signer/config/ca" { capabilities = ["create", "read", "update", "delete"] }
    path "ssh-host-signer/roles/*" { capabilities = ["create", "read", "update", "delete", "list"] }

    path "auth/token/lookup-self" { capabilities = ["read"] }
  EOT
}
