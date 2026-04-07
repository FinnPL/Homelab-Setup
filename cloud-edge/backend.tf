terraform {
  backend "s3" {
    bucket       = "finnpl-homelab-tfstate-1766068376"
    key          = "cloud-edge/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
