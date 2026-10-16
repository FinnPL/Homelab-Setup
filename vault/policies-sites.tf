# Per-site policies for the deploy workflows.
# The *-ssh policies only reach roles bound to main and plan roles get the kv reads alone.
resource "vault_policy" "vieta" {
  name = "vieta"

  policy = <<-EOT
    path "kv/data/vieta/*" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "vieta_ssh" {
  name = "vieta-ssh"

  policy = <<-EOT
    path "ssh-client-signer/sign/${vault_ssh_secret_backend_role.homelab.name}" {
      capabilities = ["create", "update"]
    }
    path "ssh-host-signer/sign/${vault_ssh_secret_backend_role.homelab_host.name}" {
      capabilities = ["create", "update"]
    }
  EOT
}

resource "vault_policy" "cloud_edge_plan" {
  name = "cloud-edge-plan"

  policy = <<-EOT
    path "kv/data/cloud-edge/oci" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "cloud_edge" {
  name = "cloud-edge"

  policy = <<-EOT
    path "kv/data/cloud-edge/*" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "cloud_edge_ssh" {
  name = "cloud-edge-ssh"

  policy = <<-EOT
    path "ssh-client-signer/sign/${vault_ssh_secret_backend_role.oci_edge.name}" {
      capabilities = ["create", "update"]
    }
    path "ssh-host-signer/sign/${vault_ssh_secret_backend_role.oci_edge_host.name}" {
      capabilities = ["create", "update"]
    }
  EOT
}

# The tailnet layer owns the operator's OAuth client, so it writes the secret ESO reads.
resource "vault_policy" "tailscale" {
  name = "tailscale"

  policy = <<-EOT
    path "kv/data/apps/tailscale" { capabilities = ["create", "read", "update"] }
    path "kv/metadata/apps/tailscale" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "tailscale_plan" {
  name = "tailscale-plan"

  policy = <<-EOT
    path "kv/data/apps/tailscale" { capabilities = ["read"] }
    path "kv/metadata/apps/tailscale" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "minerva" {
  name = "minerva"

  policy = <<-EOT
    path "kv/data/minerva/*" { capabilities = ["read"] }
  EOT
}
