terraform {
  backend "s3" {
    bucket       = "finnpl-homelab-tfstate-1766068376"
    key          = "01-network/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}