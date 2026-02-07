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
  default     = "v0.13.0"
}