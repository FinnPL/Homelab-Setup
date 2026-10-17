resource "tailscale_acl" "policy" {
  acl = file("${path.module}/policy.hujson")
}
