<div align="center">

# Homelab Setup

[![Orchestrator](https://github.com/FinnPL/Homelab-Setup/actions/workflows/main-deploy.yaml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/main-deploy.yaml)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?style=flat&logo=github-actions&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-EE0000?style=flat&logo=ansible&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1628?style=flat&logo=helm&logoColor=white)
<br />
![Talos](https://img.shields.io/badge/Talos_Linux-364EBD?style=flat&logo=linux&logoColor=white)
![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-E57024?style=flat&logo=proxmox&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-20B2AA?style=flat&logo=cilium&logoColor=white)
![UniFi](https://img.shields.io/badge/Ubiquiti_UniFi-0559C9?style=flat&logo=ubiquiti&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=flat&logo=cloudflare&logoColor=white)


A GitOps-driven multi-site homelab managed by ArgoCD, bootstrapped via Terraform IaC and CI/CD to deploy a Talos Kubernetes cluster on Proxmox with Cilium CNI and a full OTel-based Prometheus/Loki monitoring stack.
</div>

---

## Overview

### Sites

Three sites with distinct roles, each deployed by its own GitHub Actions workflow:

| Site | Role | Platform | Deploys via |
|:-----|:-----|:---------|:------------|
| **Vieta** | Primary homelab: Kubernetes cluster, services, storage | Talos K8s on Proxmox | `main-deploy.yaml` |
| **Minerva** | Secondary site: lightweight services | Docker Compose | `minerva-deploy.yaml` |
| **Cloud Edge** | Public-facing edge: TLS termination, VPN tunneling, management | NixOS on Oracle Cloud (ARM) | `cloud-edge.yaml` |

### Technology Stack

| Domain | Tools |
|:-------|:------|
| **IaC & CI/CD** | Terraform (S3-backed state), Ansible, GitHub Actions, Tailscale runner, Renovate |
| **Compute** | Proxmox (Intel NUC), Talos Linux, NixOS, Raspberry Pi workers |
| **Orchestration** | Kubernetes, ArgoCD (App of Apps), Helm |
| **Networking** | Cilium (CNI, kube-proxy replacement, Gateway API, Hubble), UniFi, Cloudflare, HAProxy, WireGuard, Tailscale |
| **Storage** | NFS CSI, local-path-provisioner *(planned: Democratic CSI on TrueNAS)* |
| **Data** | CloudNativePG, Crossplane (DBaaS) |
| **Observability** | Prometheus, Alertmanager, Grafana, Loki, Alloy |
| **Identity & Secrets** | Authentik (SSO), External Secrets Operator, cert-manager *(planned: Vault)* |
| **DNS** | Blocky (filtering), Unbound (DNSSEC + DoT upstream), Cloudflare |

### CI/CD Pipeline

Push to `main` triggers an orchestrator workflow that detects which layers changed and runs them in order. PRs get a Terraform plan comment for review. Tailscale connects the GitHub runner to the homelab network. Renovate keeps dependencies (Helm charts, container images, Terraform providers, Action versions, Nix flake refs, and more) up to date by opening PRs against the repo.

---

## Vieta Site

The primary site, structured as four Terraform layers plus the applications deployed by ArgoCD. State flows forward via remote state outputs.

| Layer | Scope |
|:------|:------|
| [`00-global`](#) | S3 state backend, shared config |
| [`01-network`](#01-network) | UniFi VLANs, firewall, DHCP, DNS; Cloudflare records |
| [`02-infrastructure`](#02-infrastructure) | Proxmox VMs/LXCs, Talos cluster bootstrap, NFS |
| [`03-services`](#03-services-cluster-platform) | Cluster platform (CNI, certs, ingress, secrets) |
| [ArgoCD](#argocd--applications) | Applications via GitOps |

### 01 Network

Manages the Vieta site network through the UniFi controller API and Cloudflare. Covers VLANs, zone-based firewall policies, switch port profiles, static DHCP reservations with local DNS, and Cloudflare DNS records.

#### VLANs

| VLAN | ID | Subnet | Purpose |
|:-----|:---|:-------|:--------|
| Default | 10 | `10.10.10.0/24` | Consumer devices, IoT, mDNS enabled |
| Athena | 20 | `10.10.1.0/24` | Homelab infrastructure, network-isolated |

#### Zone-Based Firewall

Inter-VLAN traffic is blocked by default. Only SSH, HTTPS, and SMB are permitted from Default into Athena.

| Rule | From | To | Ports | Action |
|:-----|:-----|:---|:------|:-------|
| Service access | Internal (Default) | Athena | 22, 443, 445 | Allow |
| VPN gateway | Athena | External (`10.0.3.2`) | All | Allow |
| VPN lockout | Internal (Default) | External (`10.0.3.2`) | All | Block |

#### DNS

Cloudflare manages the `lippok.dev` zone. A wildcard and root A record are created in `03-services` pointing to the Kubernetes Gateway LoadBalancer IP. Oracle records are managed under `cloud-edge`.

| Subdomain | DNS | TLS terminated at | Use case |
|:----------|:----|:------------------|:---------|
| `*.lippok.dev` | Local LB IP | Local Gateway | Local-only services |
| `*.cloud.lippok.dev` | Oracle IP | HAProxy | Cloud-hosted services |
| `*.relay.lippok.dev` | Oracle IP | HAProxy TLS passthrough to Local | Proxied services |

#### DoH Relay

1. **Entry:** Client (DoH) to `dns.relay.lippok.dev` via Oracle HAProxy.
2. **Tunnel:** TLS relay over WireGuard to homelab (E2EE).
3. **Homelab:** Terminates TLS and resolves through Blocky (filtering) then Unbound (DNSSEC).
4. **Upstream:** ODoH-style via VPN + DoT to 1.1.1.1.

**Validation:** `dns-check.cloud.lippok.dev` only resolves to `oci.cloud.lippok.dev` behind Blocky.

### 02 Infrastructure

Provisions VMs and containers on a Proxmox host (Intel NUC) and bootstraps a Talos-based Kubernetes cluster. All IPs and MACs are sourced from `01-network` via remote state.

#### Talos Kubernetes Cluster

- **OS:** Talos Linux: immutable, API-driven, no SSH
- **Image:** Built via Talos Image Factory with `qemu-guest-agent` extension
- **CNI:** Set to `none` at bootstrap (Cilium installed in `03-services`)
- **kube-proxy:** Disabled (Cilium takes over)

| Node Role | Count | Platform |
|:----------|:------|:---------|
| Control plane | 1 | Proxmox VM |
| Workers (general) | 3 | Raspberry Pi (Athena VLAN) |
| Worker (database) | 1 | Proxmox VM, tainted `dedicated=database:NoSchedule` |

#### NFS Server

Debian 12 LXC container with dual storage (SSD for OS, HDD for data). Exports `/srv/nfs/kubernetes` to the cluster. Proxmox firewall defaults to `DROP`; only K8s nodes and the NUC are whitelisted via IP set.

#### Outputs

Exports `kubeconfig`, `talosconfig`, cluster info, and NFS server details for the next layer.

### 03 Services (Cluster Platform)

Bootstraps all platform-level services that make the cluster operational. Reads state from both `01-network` (LB CIDR) and `02-infrastructure` (kubeconfig, NFS server). Everything here is a prerequisite for the applications managed by ArgoCD.

#### Cilium

Cilium replaces kube-proxy and serves as the cluster CNI. It handles LoadBalancer IP advertisement via L2 announcements on all nodes (the IP pool is sourced from the `01-network` output), provides ingress through the Kubernetes Gateway API (`cilium` gatewayClassName), and exposes flow-level observability through Hubble with its UI and relay.

#### Kubernetes Gateway API

A single `Gateway` resource handles all ingress with HTTP (80) and HTTPS (443) listeners. The HTTPS listener terminates TLS with a wildcard `*.lippok.dev` certificate. Services are exposed by creating `HTTPRoute` resources in their own namespaces.

#### cert-manager

- **Issuer:** Let's Encrypt (production ACME)
- **Challenge:** DNS-01 via Cloudflare API token
- **Certificate:** Wildcard `*.lippok.dev` + root, stored in the `gateway` namespace

#### NFS Storage

The cluster mounts persistent volumes via `csi-driver-nfs`, talking to the NFS server provisioned in `02-infrastructure` (IP and export path passed through outputs). The default StorageClass `nfs-client` provides NFS 4.1 mounts to all pods.

> **Why NFS?** Several seemingly odd decisions in this cluster trace back to one constraint: avoiding SD card wear on the Raspberry Pi workers. Local PVCs on the Pis would burn through SD cards quickly under typical Kubernetes write patterns, so persistent storage is offloaded to NFS. The same constraint is why the database worker is a dedicated VM on the NUC (tainted `dedicated=database:NoSchedule`) rather than scheduling Postgres onto the Pis.

> **Planned migration:** Once the new NAS/TrueNAS is online, remove the temporary Proxmox database worker VM, NFS LXC, and `local-path-provisioner`. Switch to Democratic CSI for dynamic ZFS-backed iSCSI/NFS provisioning and snapshots, with a new Talos database VM hosted on TrueNAS.

#### External Secrets Operator

Manages secret distribution across namespaces.

- **Backend (current):** Kubernetes secrets in a dedicated `secret-store` namespace, seeded by Terraform.
- **Backend (planned):** HashiCorp Vault
- **ClusterSecretStore** reads from the temporary backend via a dedicated ServiceAccount + RBAC

### ArgoCD & Applications

ArgoCD is deployed via Helm in `03-services`. Everything beyond the platform services is managed through ArgoCD's **App of Apps** pattern: a root Application watches the `apps/` directory in this repo and automatically syncs each application definition to the cluster.

#### Platform

| Service | Role |
|:--------|:-----|
| **ArgoCD** | GitOps controller: self-managed via App of Apps |
| **CloudNative-PG** | PostgreSQL operator; provides databases for services |
| **Crossplane** | DBaaS: provisions Postgres databases, PgBouncer, and credentials |
| **Local Path Provisioner** | Node-local dynamic storage for DBs |

#### Observability

A unified OTel-based stack for metrics, logs, and alerting.

| Service | Role |
|:--------|:-----|
| **kube-prometheus-stack** | Prometheus + Alertmanager + Grafana for cluster-wide metrics and dashboards |
| **Loki** | Log aggregation backend (single-binary, filesystem-backed) |
| **Alloy** | Telemetry collection agent: DaemonSet (node logs/metrics) + StatefulSet (syslog from Talos, Proxmox, UniFi) |

#### Authentication

| Service | Role |
|:--------|:-----|
| **Authentik** | Self-hosted identity provider and SSO; backed by CNPG PostgreSQL |

#### Networking & DNS

| Service | Role |
|:--------|:-----|
| **Tailscale Operator** | Kubernetes-native Tailscale integration for secure mesh access |
| **Blocky + Unbound** | Internal DNS stack: Blocky for filtering/caching, Unbound as DNSSEC-validating resolver with DoT upstream |
| **Gateway External Routes** | Nginx reverse-proxy deployed as `HTTPRoute` targets to bridge non-Kubernetes hosts (NAS, Proxmox, router) into cluster ingress |

#### Applications

| Service | Role |
|:--------|:-----|
| **Gatus** | Endpoint health monitoring and status page; Discord alerting, PostgreSQL-backed history |
| **IT-Tools** | Self-hosted suite of developer and network utilities |

---

## Minerva Site

Secondary site running services via Docker Compose. Deployed via `minerva-deploy.yaml`.

---

## Cloud Edge

Public-facing edge node on Oracle Cloud's Always Free ARM tier. Provides:

- **HAProxy:** SNI routing for `*.cloud` and `*.relay` subdomains
- **WireGuard:** encrypted tunnel back to the homelab
- **Tailscale:** out-of-band management

| Layer | Scope |
|:------|:------|
| `cloud-edge/*.tf` | OCI instance, VCN, security list, edge subnet/firewall, Cloudflare `*.cloud` and `*.relay` records |
| `cloud-edge/nixos/` | NixOS flake (deployed via nixos-anywhere); full host configuration for the `oracle-edge` node |
