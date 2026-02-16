output "kubeconfig" {
  description = "Kubernetes config for accessing the cluster"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talos client configuration for talosctl"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "cluster_info" {
  description = "Kubernetes cluster information"
  value = {
    name               = var.cluster_name
    endpoint           = local.cluster_endpoint
    talos_version      = var.talos_version
    kubernetes_version = var.kubernetes_version
    controlplane_ip    = local.talos_controlplane_ip
  }
}

output "nfs_server" {
  description = "NFS server information for Kubernetes storage"
  value = {
    ip           = local.nfs_server_ip
    export_path  = "/srv/nfs/kubernetes"
    storage_size = var.nfs_server_config.data_disk_size
  }
}

output "postgres_server" {
  description = "Connection details for the shared Postgres server"
  value = {
    ip       = local.postgres_server_ip
    password = var.postgres_admin_password
  }
  sensitive = true
}

output "vault_server" {
  description = "HashiCorp Vault server details"
  value = {
    ip       = local.vault_server_ip
    ui_url   = "http://${local.vault_server_ip}:8200"
    api_addr = "http://${local.vault_server_ip}:8200"
  }
}