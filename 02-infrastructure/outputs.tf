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
