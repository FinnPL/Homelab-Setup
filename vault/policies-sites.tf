# Per-site read policies for the deploy workflows.
resource "vault_policy" "vieta" {
  name = "vieta"

  policy = <<-EOT
    path "kv/data/vieta/*" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
    path "kv/data/ci/tailscale" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "cloud_edge" {
  name = "cloud-edge"

  policy = <<-EOT
    path "kv/data/cloud-edge/*" { capabilities = ["read"] }
    path "kv/data/cloudflare" { capabilities = ["read"] }
    # The edge node joins the same tailnet as the cluster operator.
    path "kv/data/apps/tailscale" { capabilities = ["read"] }
  EOT
}

resource "vault_policy" "minerva" {
  name = "minerva"

  policy = <<-EOT
    path "kv/data/minerva/*" { capabilities = ["read"] }
  EOT
}
