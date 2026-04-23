variable "name" {
  description = "Name prefix for the relay resources (ConfigMap/Deployment/Service all share this)."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace to deploy the relay into."
  type        = string
}

variable "listen_port" {
  description = "TCP port the nginx container listens on (non-privileged, must be >= 1024)."
  type        = number
  default     = 8443

  validation {
    condition     = var.listen_port >= 1024 && var.listen_port <= 65535
    error_message = "listen_port must be in 1024-65535 (container runs as non-root)."
  }
}

variable "service_port" {
  description = "Port exposed on the relay Service (what TLSRoute/HTTPRoute backendRefs target)."
  type        = number
  default     = 443
}

variable "upstream_host" {
  description = "Upstream DNS name or IP the relay forwards to. A DNS name is resolved at connection time via the `resolver` directive; an IP is used verbatim."
  type        = string
}

variable "upstream_port" {
  description = "Upstream TCP port."
  type        = number
  default     = 443
}

variable "replicas" {
  description = "Number of relay pod replicas."
  type        = number
  default     = 2
}

variable "image" {
  description = "Nginx image. Must include the stream module (stock nginx does)."
  type        = string
  default     = "nginxinc/nginx-unprivileged:1.29-alpine"
}

variable "resolver" {
  description = "DNS resolver nginx uses to resolve upstream_host at connection time. Must match in-cluster kube-dns."
  type        = string
  default     = "kube-dns.kube-system.svc.cluster.local"
}

variable "resolver_valid" {
  description = "How long nginx caches a successful DNS lookup before re-resolving."
  type        = string
  default     = "10s"
}

variable "proxy_connect_timeout" {
  description = "nginx proxy_connect_timeout."
  type        = string
  default     = "5s"
}

variable "proxy_timeout" {
  description = "nginx proxy_timeout (idle read/write timeout on the proxied connection)."
  type        = string
  default     = "30s"
}

variable "resources" {
  description = "Container resource requests/limits."
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "10m"
      memory = "32Mi"
    }
    limits = {
      cpu    = "100m"
      memory = "128Mi"
    }
  }
}
