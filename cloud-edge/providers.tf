terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "6.37.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.18.0"
    }
  }
}

provider "oci" {
  tenancy_ocid = var.oci_tenancy_ocid
  user_ocid    = var.oci_user_ocid
  fingerprint  = var.oci_fingerprint
  private_key  = var.oci_private_key
  region       = var.oci_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
