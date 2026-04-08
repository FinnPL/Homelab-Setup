variable "kubeconfig_path" {
  description = "Path to the K3s kubeconfig file (fetched from edge node by CI)"
  type        = string
  default     = "./kubeconfig.yaml"
}

variable "gateway_api_version" {
  description = "Version of Gateway API CRDs to install"
  type        = string
  # renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
  default = "v1.4.1"
}

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  # renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io/
  default = "1.19.2"
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version"
  type        = string
  # renovate: datasource=helm depName=cert-manager registryUrl=https://charts.jetstack.io
  default = "v1.17.2"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token for cert-manager DNS-01 challenges"
  type        = string
  sensitive   = true
  default     = ""
}

variable "acme_email" {
  description = "Email address for Let's Encrypt certificate registration"
  type        = string
  default     = ""
}
