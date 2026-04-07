terraform {
  backend "s3" {
    bucket = "finnpl-homelab-tfstate-1766068376"
    key    = "cloud-edge-k3s-services/terraform.tfstate"
    region = "eu-central-1"
  }
}
