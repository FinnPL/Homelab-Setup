# OCI Authentication

variable "oci_tenancy_ocid" {
  description = "OCID of the OCI tenancy"
  type        = string
}

variable "oci_user_ocid" {
  description = "OCID of the OCI user for API access"
  type        = string
}

variable "oci_fingerprint" {
  description = "Fingerprint of the OCI API signing key"
  type        = string
}

variable "oci_private_key" {
  description = "PEM-encoded private key for OCI API authentication"
  type        = string
  sensitive   = true
}

variable "oci_region" {
  description = "OCI region to deploy resources in"
  type        = string
  default     = "eu-frankfurt-1"
}

variable "oci_compartment_ocid" {
  description = "OCID of the compartment to create resources in"
  type        = string
}

# Compute Instance

variable "instance_name" {
  description = "Display name for the edge node instance"
  type        = string
  default     = "oracle-edge-01"
}

variable "instance_shape" {
  description = "OCI compute shape (Always Free: VM.Standard.A1.Flex)"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs to allocate (Always Free max total: 4)"
  type        = number
  default     = 2
}

variable "instance_memory_gb" {
  description = "Memory in GB to allocate (Always Free max total: 24)"
  type        = number
  default     = 6
}

variable "instance_boot_volume_gb" {
  description = "Boot volume size in GB (Always Free max: 200 total, up to 50 per volume)"
  type        = number
  default     = 50
}

# SSH Access

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

# Networking

variable "vcn_cidr" {
  description = "CIDR block for the VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# Cloudflare DNS

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with Edit Zone permissions"
  type        = string
  sensitive   = true
}
