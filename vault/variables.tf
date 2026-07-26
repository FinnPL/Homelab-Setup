variable "vault_address" {
  description = "URL of the Vault server"
  type        = string
  default     = "https://vault.cloud.lippok.dev"
}

variable "github_repository" {
  description = "owner/repo for GitHub Actions OIDC claim binding"
  type        = string
  default     = "FinnPL/Homelab-Setup"
}
