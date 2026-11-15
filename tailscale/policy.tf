# policy.hujson is a template: its addresses come from inventory/.
resource "tailscale_acl" "policy" {
  acl = templatefile("${path.module}/policy.hujson", {
    vieta   = jsondecode(file("${path.module}/../inventory/vieta.json")).inventory.vieta
    minerva = jsondecode(file("${path.module}/../inventory/minerva.json")).inventory.minerva
  })
}
