variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit on fplnet.net and the /44 reverse zone"
  type        = string
  sensitive   = true
}
