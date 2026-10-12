# Zone-wide settings. They only act on proxied names.
locals {
  zone_settings = {
    ssl               = "strict"
    always_use_https  = "on"
    min_tls_version   = "1.2"
    tls_1_3           = "on"
    rocket_loader     = "off"
    email_obfuscation = "on"
  }
}

resource "cloudflare_zone_setting" "main" {
  for_each = local.zone_settings

  zone_id    = data.cloudflare_zone.main.id
  setting_id = each.key
  value      = each.value
}

resource "cloudflare_zone_setting" "hsts" {
  zone_id    = data.cloudflare_zone.main.id
  setting_id = "security_header"
  value = {
    strict_transport_security = {
      enabled            = true
      max_age            = 15552000
      include_subdomains = false
      preload            = false
      nosniff            = true
    }
  }
}

resource "cloudflare_ruleset" "cache" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      description = "Homepage: cache, respecting origin Cache-Control"
      expression  = "(http.host eq \"lippok.dev\")"
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode = "respect_origin"
        }
        browser_ttl = {
          mode = "respect_origin"
        }
      }
    }
  ]
}
