# lippok.dev zone settings, the cache rule and the apex record.

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

# lippok.dev: Cloudflare proxies it to the FPLNET edges' anycast address, where nginx serves the
# site with a Cloudflare Origin CA certificate (fplnet/nixos/modules/lippok-dev.nix).
resource "cloudflare_dns_record" "apex_homepage" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  type    = "AAAA"
  ttl     = 1
  content = "2a0c:b641:f91::80"
  proxied = true
}

import {
  for_each = local.zone_settings
  to       = cloudflare_zone_setting.main[each.key]
  id       = "8c35cb20eeb17f6cc81bb4bc072df7a4/${each.key}"
}

import {
  to = cloudflare_zone_setting.hsts
  id = "8c35cb20eeb17f6cc81bb4bc072df7a4/security_header"
}

import {
  to = cloudflare_ruleset.cache
  id = "zones/8c35cb20eeb17f6cc81bb4bc072df7a4/44673bbb2290495fa2716baabc79248c"
}

import {
  to = cloudflare_dns_record.apex_homepage
  id = "8c35cb20eeb17f6cc81bb4bc072df7a4/e2dee9a94beed1e8f9e7d2592bff8315"
}
