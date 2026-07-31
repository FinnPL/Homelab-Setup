# Per-site read policies for the deploy workflows.
resource "vault_policy" "vieta" {
  name = "vieta"

  policy = <<-EOT
    path "kv/data/vieta/*" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
    path "kv/data/ci/tailscale" { capabilities = ["read"] }
    path "ssh-client-signer/sign/${vault_ssh_secret_backend_role.homelab.name}" {
      capabilities = ["create", "update"]
    }
    path "ssh-host-signer/sign/${vault_ssh_secret_backend_role.homelab_host.name}" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "cloud_edge" {
  name = "cloud-edge"

  policy = <<-EOT
    path "kv/data/cloud-edge/*" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
    # The edge node joins the same tailnet as the cluster operator.
    path "kv/data/apps/tailscale" { capabilities = ["read"] }
    path "ssh-client-signer/sign/${vault_ssh_secret_backend_role.oci_edge.name}" {
      capabilities = ["create", "update"]
    }
    path "ssh-host-signer/sign/${vault_ssh_secret_backend_role.oci_edge_host.name}" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "minerva" {
  name = "minerva"

  policy = <<-EOT
    path "kv/data/minerva/*" { capabilities = ["read"] }
  EOT
}
