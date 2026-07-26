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

    path "auth/token/lookup-self" { capabilities = ["read"] }
  EOT
}
