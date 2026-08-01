resource "vault_mount" "ssh_client_signer" {
  path        = "ssh-client-signer"
  type        = "ssh"
  description = "User CA — signs ephemeral CI keys so no long-lived SSH private key is stored"
}

# Vault generates and keeps the private half; only the public key ever leaves.
resource "vault_ssh_secret_backend_ca" "client_signer" {
  backend              = vault_mount.ssh_client_signer.path
  generate_signing_key = true
  key_type             = "ed25519"
}

locals {
  ssh_cert_ttl = "3600"

  ssh_cert_extensions = {
    permit-pty = ""
  }

  ssh_cert_key_id = "{{role_name}}-{{token_display_name}}-{{public_key_hash}}"
}

resource "vault_ssh_secret_backend_role" "oci_edge" {
  backend = vault_mount.ssh_client_signer.path
  name    = "oci-edge"

  key_type                = "ca"
  allow_user_certificates = true
  allowed_users           = "root"
  default_user            = "root"

  default_extensions = local.ssh_cert_extensions
  allowed_extensions = join(",", keys(local.ssh_cert_extensions))

  ttl     = local.ssh_cert_ttl
  max_ttl = local.ssh_cert_ttl

  key_id_format = local.ssh_cert_key_id
}

resource "vault_ssh_secret_backend_role" "homelab" {
  backend = vault_mount.ssh_client_signer.path
  name    = "homelab"

  key_type                = "ca"
  allow_user_certificates = true
  allowed_users           = "root"
  default_user            = "root"

  default_extensions = local.ssh_cert_extensions
  allowed_extensions = join(",", keys(local.ssh_cert_extensions))

  ttl     = local.ssh_cert_ttl
  max_ttl = local.ssh_cert_ttl

  key_id_format = local.ssh_cert_key_id
}

output "ssh_client_ca_public_key" {
  value = vault_ssh_secret_backend_ca.client_signer.public_key
}

resource "vault_mount" "ssh_host_signer" {
  path        = "ssh-host-signer"
  type        = "ssh"
  description = "Host CA — signs host keys so CI verifies hosts by certificate instead of trust-on-first-use"
}

resource "vault_ssh_secret_backend_ca" "host_signer" {
  backend              = vault_mount.ssh_host_signer.path
  generate_signing_key = true
  key_type             = "ed25519"
}

locals {
  # 90 days, in seconds. ssh-cert-converge.yaml renews both sites weekly
  ssh_host_cert_ttl = "7776000"

  # Mirrors the DHCP reservations in 01-network/static_hosts.tf
  homelab_host_principals = [
    "10.10.1.80", "nfs.athena",
    "10.10.1.90", "mesh-router.athena",
  ]
}

resource "vault_ssh_secret_backend_role" "oci_edge_host" {
  backend = vault_mount.ssh_host_signer.path
  name    = "oci-edge-host"

  key_type                = "ca"
  allow_host_certificates = true
  allow_user_certificates = false

  # The edge public IP is ephemeral the client instead pins @cert-authority to the single IP
  allowed_domains    = "*"
  allow_bare_domains = true
  allow_subdomains   = true

  ttl     = local.ssh_host_cert_ttl
  max_ttl = local.ssh_host_cert_ttl

  key_id_format = local.ssh_cert_key_id
}

resource "vault_ssh_secret_backend_role" "homelab_host" {
  backend = vault_mount.ssh_host_signer.path
  name    = "homelab-host"

  key_type                = "ca"
  allow_host_certificates = true
  allow_user_certificates = false

  allowed_domains    = join(",", local.homelab_host_principals)
  allow_bare_domains = true

  ttl     = local.ssh_host_cert_ttl
  max_ttl = local.ssh_host_cert_ttl

  key_id_format = local.ssh_cert_key_id
}

output "ssh_host_ca_public_key" {
  value = vault_ssh_secret_backend_ca.host_signer.public_key
}
