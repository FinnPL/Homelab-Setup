resource "tls_private_key" "vault_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "vault_ca" {
  private_key_pem       = tls_private_key.vault_ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87600
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature"
  ]

  subject {
    common_name  = "vault-ca.lippok.dev"
    organization = "Homelab"
  }
}

resource "tls_private_key" "vault_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "vault_server" {
  private_key_pem = tls_private_key.vault_server.private_key_pem
  dns_names       = ["vault.lippok.dev"]
  ip_addresses    = [local.vault_server_ip]

  subject {
    common_name  = "vault.lippok.dev"
    organization = "Homelab"
  }
}

resource "tls_locally_signed_cert" "vault_server" {
  cert_request_pem      = tls_cert_request.vault_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.vault_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.vault_ca.cert_pem
  validity_period_hours = 19800
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth"
  ]
}
