variable "cloudflare_api_token" {
  description = "Cloudflare API Token with Edit Zone permissions"
  type        = string
  sensitive   = true
}

variable "acme_email" {
  description = "Email address for Let's Encrypt certificate registration"
  type        = string
}

variable "gateway_api_version" {
  description = "Version of Gateway API CRDs to install"
  type        = string
  # renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
  default = "v1.4.1"
}

variable "crossplane_provider_sql_version" {
  description = "Version of the Crossplane SQL Provider"
  type        = string
  # renovate: datasource=docker depName=xpkg.upbound.io/crossplane-contrib/provider-sql
  default = "v0.14.0"
}

# Temporary Secrets until Vault is deployed:

variable "authentik_secret_key" {
  description = "Authentik secret key for session signing"
  type        = string
  sensitive   = true
}

variable "argocd_oidc_client_secret" {
  description = "OIDC client secret shared between Authentik and ArgoCD"
  type        = string
  sensitive   = true
}

variable "grafana_oidc_client_secret" {
  description = "OIDC client secret shared between Authentik and Grafana"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth Client ID"
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_secret" {
  description = "Tailscale OAuth Client Secret"
  type        = string
  sensitive   = true
}

variable "gatus_discord_webhook_url" {
  description = "Discord webhook URL for Gatus uptime alerts"
  type        = string
  sensitive   = true
}

variable "alertmanager_discord_webhook_url" {
  description = "Discord webhook URL for Alertmanager metrics and logs alerts"
  type        = string
  sensitive   = true
}

variable "unifi_exporter_username" {
  description = "UniFi exporter API username"
  type        = string
  sensitive   = true
}

variable "unifi_exporter_password" {
  description = "UniFi exporter API password"
  type        = string
  sensitive   = true
}
