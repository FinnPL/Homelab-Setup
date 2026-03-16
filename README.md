<div align="center">

# Homelab Setup

[![Orchestrator](https://github.com/FinnPL/Homelab-Setup/actions/workflows/main-deploy.yaml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/main-deploy.yaml)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1628?style=flat&logo=helm&logoColor=white)
<br />
![Talos](https://img.shields.io/badge/Talos_Linux-364EBD?style=flat&logo=linux&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-E57024?style=flat&logo=proxmox&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-20B2AA?style=flat&logo=cilium&logoColor=white)
![UniFi](https://img.shields.io/badge/Ubiquiti_UniFi-0559C9?style=flat&logo=ubiquiti&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat&logo=cloudflare&logoColor=white)


A GitOps-driven multi-site homelab leveraging IaC via Terraform and CI/CD to orchestrate a Talos Kubernetes cluster with Cilium CNI on Proxmox via ArgoCD.

</div>

## IaC Overview

Four Terraform layers, deployed sequentially via GitHub Actions. Each layer has its own S3-backed state and feeds outputs into the next.

| Layer | Scope | What it configures |
|:------|:------|:-------------------|
| `00-global` | S3 state backend, shared config | AWS S3 bucket for Terraform state |
| `01-network` | VLANs, firewall, DHCP, DNS | UniFi networks, Cloudflare DNS records |
| `02-infrastructure` | VMs, Kubernetes bootstrap, storage | Proxmox VMs/LXCs, Talos Linux cluster |
| `03-services` | Cluster platform bootstrapping (CNI, certs, ingress, secrets) | Helm releases, K8s resources, Cloudflare DNS |
| **ArgoCD** | Application workloads via GitOps | App of Apps pattern from this repo |

### CI/CD Pipeline

Push to `main` triggers an orchestrator workflow that detects which layers changed and runs them in order. PRs get a Terraform plan comment for review. Tailscale connects the GitHub runner to the homelab network.

---

## 01 Network

Manages the entire Vieta site network through the UniFi controller API and Cloudflare. This includes VLANs, zone-based firewall policies, switch port profiles, static DHCP reservations with local DNS, and Cloudflare DNS records.

### VLANs

| VLAN | ID | Subnet | Purpose |
|:-----|:---|:-------|:--------|
| Default | 10 | `10.10.10.0/24` | Consumer devices, IoT, mDNS enabled |
| Athena | 20 | `10.10.1.0/24` | Homelab infrastructure, network-isolated |

### Zone-Based Firewall

| Rule | From | To | Ports | Action |
|:-----|:-----|:---|:------|:-------|
| Service access | Internal (Default) | Athena | 22, 443, 445 | Allow |
| VPN gateway | Athena | External (`10.0.3.2`) | All | Allow |
| VPN lockout | Internal (Default) | External (`10.0.3.2`) | All | Block |

Inter-VLAN traffic is blocked by default (network isolation). Only SSH, HTTPS, and SMB are permitted from Default into Athena.

### DNS

Cloudflare manages the `lippok.dev` zone. A wildcard and root A record are created in `03-services` pointing to the Kubernetes Gateway LoadBalancer IP.

---

## 02 Infrastructure

Provisions VMs and containers on a Proxmox host (Intel NUC) and bootstraps a Talos-based Kubernetes cluster. All IPs and MACs are sourced from `01-network` via remote state.

### Talos Kubernetes Cluster

- **OS:** Talos Linux -- immutable, API-driven, no SSH
- **Image:** Built via Talos Image Factory with `qemu-guest-agent` extension
- **CNI:** Set to `none` at bootstrap (Cilium installed in `03-services`)
- **kube-proxy:** Disabled (Cilium takes over)
- **KubePrism:** Enabled on port 7445 for HA API server discovery

| Node Role | Count | Platform |
|:----------|:------|:---------|
| Control plane | 1 | Proxmox VM |
| Workers (general) | 3 | Bare-metal (Athena VLAN) |
| Worker (database) | 1 | Proxmox VM, tainted `dedicated=database:NoSchedule` |

### NFS Server

Debian 12 LXC container with dual storage (SSD for OS, HDD for data). Exports `/srv/nfs/kubernetes` to the cluster. Proxmox firewall defaults to `DROP`; only K8s nodes and the NUC are whitelisted via IP set.

### Outputs

Exports `kubeconfig`, `talosconfig`, cluster info, and NFS server details for the next layer.

---

## 03 Services (Cluster Platform)

Bootstraps all platform-level services that make the cluster operational. Reads state from both `01-network` (LB CIDR) and `02-infrastructure` (kubeconfig, NFS server). Everything here is a prerequisite for the application workloads managed by ArgoCD.

### Cilium

Replaces kube-proxy and acts as the cluster CNI.

| Feature | Status |
|:--------|:-------|
| kube-proxy replacement | Enabled |
| L2 Announcements | Enabled (all nodes) |
| Gateway API | Enabled (`cilium` gatewayClassName) |
| Hubble (observability) | Enabled with UI and relay |
| LoadBalancer IP Pool | Sourced from `01-network` output |

### Kubernetes Gateway API

A single `Gateway` resource handles all ingress with HTTP (80) and HTTPS (443) listeners. The HTTPS listener terminates TLS with a wildcard `*.lippok.dev` certificate. Services are exposed by creating `HTTPRoute` resources in their own namespaces.

### cert-manager

- **Issuer:** Let's Encrypt (production ACME)
- **Challenge:** DNS-01 via Cloudflare API token
- **Certificate:** Wildcard `*.lippok.dev` + root, stored in the `gateway` namespace

### NFS Storage

| Component | Details |
|:----------|:--------|
| CSI Driver | `csi-driver-nfs` |
| StorageClass | `nfs-client` (default), NFS 4.1 |
| NFS Server | IP and export path from `02-infrastructure` outputs |

### External Secrets Operator

Manages secret distribution across namespaces.

- **Backend (current):** Kubernetes secrets in a dedicated `secret-store` namespace
- **Backend (planned):** HashiCorp Vault
- **ClusterSecretStore** reads from the temporary backend via a dedicated ServiceAccount + RBAC

Terraform seeds the initial secrets (Authentik, ArgoCD OIDC, Tailscale OAuth, CNPG superuser).

---

## ArgoCD GitOps

Deployed via Helm in `03-services`. All application workloads beyond the platform services are managed through ArgoCD's **App of Apps** pattern. A root Application watches the `apps/` directory in this repo and automatically syncs each application definition to the cluster.
