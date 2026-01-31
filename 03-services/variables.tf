variable "cloudflare_api_token" {
  description = "Cloudflare API Token with Edit Zone permissions"
  type        = string
  sensitive   = true
}

variable "gateway_api_version" {
  description = "Version of Gateway API CRDs to install"
  # renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
  default = "v1.0.0"
}