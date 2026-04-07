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

locals {
  oci_tenancy_ocid = trimspace(var.oci_tenancy_ocid)
  oci_user_ocid    = trimspace(var.oci_user_ocid)
  oci_fingerprint  = trimspace(var.oci_fingerprint)
  # Support both multiline PEM secrets and single-line values with escaped newlines.
  oci_private_key = replace(
    replace(
      replace(trimspace(var.oci_private_key), "\\n", "\n"),
      "\\r",
      "",
    ),
    "\r",
    "",
  )
  oci_region           = trimspace(var.oci_region)
  oci_compartment_ocid = trimspace(var.oci_compartment_ocid)
}

provider "oci" {
  tenancy_ocid = local.oci_tenancy_ocid
  user_ocid    = local.oci_user_ocid
  fingerprint  = local.oci_fingerprint
  private_key  = local.oci_private_key
  region       = local.oci_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
