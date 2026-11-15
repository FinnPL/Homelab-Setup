terraform {
  # The key predates the directory move; a new key would start from an empty state.
  backend "s3" {
    bucket       = "finnpl-homelab-tfstate-1766068376"
    key          = "02-infrastructure/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
