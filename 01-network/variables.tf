variable "cloudflare_api_token" {
  description = "Cloudflare API Token with Edit Zone permissions"
  type        = string
  sensitive   = true
}

variable "unifi_api_key" {
  description = "UniFi API Key for UniFi Controller"
  type        = string
  sensitive   = true
}

variable "unifi_api_url" {
  description = "URL of the UniFi Controller (e.g., https://192.168.1.1)"
  type        = string
}

variable "unifi_insecure" {
  description = "Skip TLS verification (set to true for self-signed certs)"
  type        = bool
  default     = true
}
