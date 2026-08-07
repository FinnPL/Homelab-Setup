resource "tailscale_acl" "policy" {
  acl = file("${path.module}/policy.hujson")
}

import {
  to = tailscale_acl.policy
  id = "acl"
}
