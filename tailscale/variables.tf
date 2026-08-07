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
