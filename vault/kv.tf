resource "vault_mount" "kv" {
  path        = "kv"
  type        = "kv-v2"
  description = "Static homelab secrets (CI credentials, ESO-consumed app secrets)"

  options = {
    version = "2"
  }
}
