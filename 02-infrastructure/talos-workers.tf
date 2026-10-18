data "talos_machine_configuration" "worker" {
  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version      = local.talos_version
  kubernetes_version = local.kubernetes_version

  config_patches = concat(local.talos_base_patches, [
    local.talos_install_patch.pi,
    local.talos_nic_patch.pi,
  ])
}

resource "talos_machine_configuration_apply" "workers" {
  for_each = local.talos_workers

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value
  endpoint                    = each.value

  depends_on = [
    talos_machine_bootstrap.this
  ]
}
