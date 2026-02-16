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

# Static VM MAC addresses for DHCP reservations
variable "host_vm_macs" {
  description = "Map of VM MAC addresses for DHCP reservations"
  type        = map(string)
  default = {
    talos_controlplane = "bc:24:11:00:00:60"
    windows_server     = "52:54:00:aa:00:50"
    github_runner      = "bc:24:11:00:00:70"
    nfs_server         = "bc:24:11:00:00:80"
    postgres_server    = "bc:24:11:00:00:85"
    vault_server       = "bc:24:11:00:00:90"
  }
}
