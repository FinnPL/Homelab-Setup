variable "tailnet" {
  description = "Tailnet to manage. '-' resolves to the default tailnet of the calling credential."
  type        = string
  default     = "-"
}

variable "oauth_client_id" {
  description = "Client ID of the hand-created bootstrap federated identity. Not a secret."
  type        = string
}

variable "audience" {
  description = "aud claim the bootstrap federated identity expects on the GitHub OIDC token"
  type        = string
}

variable "github_repository" {
  description = "owner/repo the federated identities bind their subject claim to"
  type        = string
  default     = "FinnPL/Homelab-Setup"
}

variable "vault_address" {
  description = "URL of the Vault server"
  type        = string
  default     = "https://vault.cloud.lippok.dev"
}
