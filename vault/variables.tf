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

variable "vieta_apiserver_issuer" {
  description = "iss claim on Vieta service-account tokens"
  type        = string
  default     = "https://10.10.1.60:6443"
}

variable "aws_tfstate_role_arn" {
  description = "IAM role the aws/ engine assumes for S3 state access"
  type        = string
  default     = "arn:aws:iam::367283415772:role/homelab-tfstate"
}
