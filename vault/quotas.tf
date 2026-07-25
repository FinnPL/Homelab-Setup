# This works because of XFF listener config x_forwarded_for_authorized_addrs for real IPs behind Caddy.

resource "vault_quota_rate_limit" "global" {
  name     = "global"
  path     = ""
  rate     = 150
  group_by = "ip"
}

resource "vault_quota_rate_limit" "userpass_login" {
  name           = "userpass-login"
  path           = "auth/userpass/"
  rate           = 10
  interval       = 60
  block_interval = 120
  group_by       = "ip"
}

resource "vault_quota_rate_limit" "github_actions_login" {
  name       = "github-actions-login"
  path       = "auth/github-actions/"
  rate       = 30
  interval   = 60
  group_by   = "ip"
  depends_on = [vault_jwt_auth_backend.github_actions]
}

resource "vault_generic_endpoint" "userpass_lockout" {
  path                 = "sys/auth/userpass/tune"
  disable_read         = true
  disable_delete       = true
  ignore_absent_fields = true

  data_json = jsonencode({
    user_lockout_threshold              = 5
    user_lockout_duration               = "30m"
    user_lockout_counter_reset_duration = "15m"
    user_lockout_disable                = false
  })
}
