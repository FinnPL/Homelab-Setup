# Short-lived client certificates for the Vieta cluster.
locals {
  cluster_pki = {
    talos = {
      path        = "pki-talos"
      description = "Talos API client CA (role from the certificate Organization)"
      common_name = "Vieta Talos client CA"
      groups = {
        admin  = "os:admin"
        reader = "os:reader"
      }
    }
    k8s = {
      path        = "pki-k8s"
      description = "Kubernetes API client CA (groups bound by 03-services RBAC)"
      common_name = "Vieta Kubernetes client CA"
      groups = {
        admin  = "homelab:admins"
        reader = "homelab:readers"
      }
    }
  }

  cluster_pki_roles = merge([
    for api, pki in local.cluster_pki : {
      for role, group in pki.groups : "${api}-${role}" => {
        api   = api
        role  = role
        group = group
      }
    }
  ]...)
}

resource "vault_mount" "cluster_pki" {
  for_each = local.cluster_pki

  path                  = each.value.path
  type                  = "pki"
  description           = each.value.description
  max_lease_ttl_seconds = 315360000

  depends_on = [vault_policy.vault_deploy]
}

resource "vault_pki_secret_backend_root_cert" "cluster" {
  for_each = local.cluster_pki

  backend     = vault_mount.cluster_pki[each.key].path
  type        = "internal"
  common_name = each.value.common_name
  ttl         = "87600h"
  key_type    = "ec"
  key_bits    = 256
  issuer_name = "root"
}

resource "vault_pki_secret_backend_role" "cluster" {
  for_each = local.cluster_pki_roles

  backend = vault_mount.cluster_pki[each.value.api].path
  name    = each.value.role

  organization      = [each.value.group]
  allow_any_name    = true
  enforce_hostnames = false
  allow_ip_sans     = false
  server_flag       = false
  client_flag       = true
  key_type          = "ec"
  key_bits          = 256
  key_usage         = ["DigitalSignature"]
  ext_key_usage     = ["ClientAuth"]
  no_store          = true

  ttl     = 3600
  max_ttl = 28800

  depends_on = [vault_pki_secret_backend_root_cert.cluster]
}

resource "vault_policy" "cluster_certs" {
  for_each = toset(["admin", "reader"])

  name = "cluster-certs-${each.key}"

  policy = <<-EOT
    path "${vault_mount.cluster_pki["talos"].path}/issue/${each.key}" { capabilities = ["create", "update"] }
    path "${vault_mount.cluster_pki["k8s"].path}/issue/${each.key}" { capabilities = ["create", "update"] }
  EOT
}

output "cluster_client_ca_pem" {
  description = "CA certificates the nodes accept client certificates from (02-infrastructure reads this)"
  value = {
    for api, cert in vault_pki_secret_backend_root_cert.cluster : api => cert.certificate
  }
}
