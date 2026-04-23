output "service_name" {
  description = "Name of the ClusterIP Service fronting the relay pods. Use as TLSRoute/HTTPRoute backendRef."
  value       = kubernetes_service_v1.relay.metadata[0].name
}

output "service_namespace" {
  description = "Namespace of the relay Service."
  value       = kubernetes_service_v1.relay.metadata[0].namespace
}

output "service_port" {
  description = "Port exposed on the relay Service."
  value       = var.service_port
}
