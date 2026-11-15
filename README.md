<div align="center">

# Homelab Setup

**A three-site homelab and its own autonomous system, declared in one repo.**<br>
Merging to `main` is the deploy: GitHub Actions applies Terraform and NixOS, ArgoCD syncs Kubernetes.

[lippok.dev](https://lippok.dev) · [fplnet.net](https://fplnet.net) · [Looking glass](https://lg.fplnet.net) · [Status](https://lippok.dev/status) · [Hardware](vieta/physical-setup.md)

![Talos](https://img.shields.io/badge/Talos-364EBD?style=flat&logo=linux&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-20B2AA?style=flat&logo=cilium&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo_CD-EF7B4D?style=flat&logo=argo&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-623CE4?style=flat&logo=terraform&logoColor=white)
![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=flat&logo=nixos&logoColor=white)
![WireGuard](https://img.shields.io/badge/WireGuard-88171A?style=flat&logo=wireguard&logoColor=white)
![Vault](https://img.shields.io/badge/Vault-FFEC6E?style=flat&logo=vault&logoColor=black)
![Proxmox](https://img.shields.io/badge/Proxmox-E57024?style=flat&logo=proxmox&logoColor=white)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/sites-dark.svg">
  <img width="100%" alt="Three FPLNET edge routers in Amsterdam, Düsseldorf and Frankfurt on a WireGuard backbone, each with a tunnel to both site gateways: gw1-aah1 routes for Vieta's Kubernetes cluster, gw1-fbg1 for Minerva's. Minerva's NAS pulls backups from Apollo in Vieta." src="docs/diagrams/sites-light.svg">
</picture>

| Site | Runs | Code |
|:-----|:-----|:-----|
| **FPLNET** | AS218255: three BGP edge routers on a WireGuard backbone, serving lippok.dev, fplnet.net and anycast site services | `fplnet/` `homepage/` |
| **Vieta** | Kubernetes on Talos: a Proxmox NUC and three Raspberry Pis in a 10" rack, joined to the backbone by gw1-aah1 | `vieta/` `charts/` |
| **Minerva** | Kubernetes on Talos VMs and the pull-only backup NAS, on one Proxmox box, joined to the backbone by gw1-fbg1 | `minerva/` `charts/` |

## How a change ships

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/delivery-dark.svg">
  <img width="100%" alt="Pull requests run pre-commit, Trivy, tflint, chart rendering with Kyverno, Terraform plans and Nix evaluation. After the merge, path filters pick one deploy workflow per directory, each with its steps and the system it lands on. Every deploy job logs in to Vault with its GitHub OIDC token." src="docs/diagrams/delivery-light.svg">
</picture>

[![Vieta: deploy](https://github.com/FinnPL/Homelab-Setup/actions/workflows/vieta-deploy.yaml/badge.svg?branch=main)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/vieta-deploy.yaml)
[![FPLNET: deploy](https://github.com/FinnPL/Homelab-Setup/actions/workflows/fplnet-deploy.yaml/badge.svg?branch=main)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/fplnet-deploy.yaml)
[![Charts: validate](https://github.com/FinnPL/Homelab-Setup/actions/workflows/charts-validate.yaml/badge.svg?branch=main)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/charts-validate.yaml)
[![SSH certs: converge](https://github.com/FinnPL/Homelab-Setup/actions/workflows/ssh-cert-converge.yaml/badge.svg?branch=main)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/ssh-cert-converge.yaml)
[![Security: Trivy](https://github.com/FinnPL/Homelab-Setup/actions/workflows/security-trivy.yaml/badge.svg?branch=main)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/security-trivy.yaml)

- **Pull request:** Terraform plans arrive as PR comments and every Nix host is evaluated. `charts-validate` renders each app and runs the cluster's real Kyverno policies against it.
- **Merge:** path filters pick the workflows. Each site's deploy runs its layers in order, skips untouched ones and upgrades Talos inside `02`, node by node.
- **GitOps:** each site's `03-services` installs its own ArgoCD and one root app. From there every `<site>/apps/<chart>.yaml` is an Application that syncs, prunes and self-heals.
- **Shared charts:** both sites render the same `charts/<chart>`, with `values.yaml` as the default and `values-<site>.yaml` for the site's differences.
- **Renovate** bumps charts, images, providers, Actions and flake inputs.

## Repository

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/repo-dark.svg">
  <img width="100%" alt="The repository in three areas. Sites: vieta/ and minerva/ with the same layout (01-network, 02-infrastructure, 03-services, root, apps), minerva/nixos for the NAS, and the shared charts/. FPLNET: fplnet/ with its NixOS flake, Terraform and deploy scripts, and homepage/. Platform: vault/, tailscale/, state-bucket/, .github/ and docs/diagrams/. All three read inventory/." src="docs/diagrams/repo-light.svg">
</picture>

`inventory/check.py` checks the numbering plan on every commit; `docs/diagrams/render.py` redraws these diagrams from the inventory.

## Vieta

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/stack-dark.svg">
  <img width="100%" alt="Vieta as layers: hardware, then the Terraform layers 01-network, 02-infrastructure and 03-services, then the apps ArgoCD deploys from charts/, grouped as GitOps, platform, security, network, observability and apps" src="docs/diagrams/stack-light.svg">
</picture>

<a href="vieta/physical-setup.md"><img align="right" height="250" hspace="10" src="docs/vieta-rack.jpg" alt="The Vieta rack from the front: UniFi gateway and switches, patch panel, the three Raspberry Pi workers and the Intel NUC"></a>

- **Talos** on Proxmox and three Pis, API only. Postgres gets its own tainted VM; everything else stores on NFS to spare the Pis' SD cards.
- **Cilium** replaces kube-proxy. It announces LoadBalancer IPs on the LAN, and pod and public service routes to gw1-aah1 over BGP. Ingress is Gateway API with a wildcard certificate.
- **Default deny** in both directions. Every allow lives in `charts/network-policies`.
- **A new service** is `charts/<name>/`, `vieta/apps/<name>.yaml` and its network policy. A database, a Vault secret and a route are one template each ([`charts/gatus/templates`](charts/gatus/templates)).
- **Rack:** a 10" mini rack, Pis powered over PoE, 3D-printed mounts; parts, layout and power in [`vieta/physical-setup.md`](vieta/physical-setup.md).
- **Planned:** a GPSDO for a stratum 1 NTP server, and a TrueNAS box replacing the NFS LXC, with democratic-csi for ZFS-backed volumes.

<br clear="right">

## FPLNET

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/traffic-dark.svg">
  <img width="100%" alt="Three classes of traffic. Edge anycast: on the nearest edge HAProxy takes TCP 443 and hands fplnet.net and lippok.dev (through Cloudflare) to nginx, HTTP/3 reaches nginx directly over UDP. Site anycast: *.relay names over IPv4 pass HAProxy unopened with PROXY v2, over IPv6 they are routed to the site anycast prefix; both cross the WireGuard backbone to a site gateway and reach the relay services in the cluster. LAN: *.lippok.dev reaches the cluster's Gateway without any edge." src="docs/diagrams/traffic-light.svg">
</picture>

| Prefix | Use | Announced by |
|:-------|:----|:-------------|
| `2a0c:b641:f91::/48` | edge anycast: lippok.dev, fplnet.net, lg.fplnet.net | every edge whose health check passes |
| `2a0c:b641:f92::/48` | site anycast: `dns.relay`, `site-data.relay` | every edge holding a route from a site gateway |
| `2a0c:b641:f94::/48` | Vieta: nodes, pods, public services | every edge with iBGP to gw1-aah1 |
| `2a0c:b641:f95::/48` | Minerva: nodes, pods, public services | every edge with iBGP to gw1-fbg1 |
| `2a0c:b641:f98::/48`, `f99`, `f9a` | er1-dus1, er1-ams1, er1-fra1 | its own edge |

- **Routing:** BIRD 3, import filters after the NLNOG guide, RPKI origin validation from two Routinators, BCP 38 source filtering, receive limits on every session.
- **Rollout:** deploy-rs, one router at a time; each waits until its BGP sessions are back up.
- **Keys:** WireGuard and BGP secrets stay in Vault and reach a router right before its switch.

## Minerva

- **Hardware:** one Proxmox box: Gigabyte B450 AORUS ELITE, Ryzen 5 5600GT, 32 GB, a Broadcom SAS3008 HBA in IT mode and two 8 TB SAS drives in a ZFS mirror.
- **Cluster:** Talos VMs, its own ArgoCD, the same charts as Vieta with `values-minerva.yaml`. gw1-fbg1, a NixOS VM, joins it to the backbone.
- **NAS:** the HBA is passed to a NixOS VM, so only that VM ever imports the ZFS pool.
- **Pull-only:** nothing writes to the NAS. It pulls from Apollo and snapshots with sanoid, out of reach of ransomware on any source.
- **By hand:** the NAS is the one host deployed by hand (`minerva/nixos/deploy.sh`), and its SSH accepts two YubiKeys and nothing else.
- **Own token:** the Proxmox token Terraform uses for the rest of the site has no rights on the NAS VM. `minerva/nas-infrastructure` mints a one-hour token over a YubiKey login and revokes it when it exits.
- **Planned:** a PoE JetKVM with the ATX extension board.

## Credentials

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/diagrams/trust-dark.svg">
  <img width="100%" alt="GitHub Actions jobs and External Secrets authenticate to Vault with short-lived tokens; Vault issues SSH client and host certificates, Talos and Kubernetes client certificates, AWS STS keys and kv secrets. The admin reaches the NAS with a YubiKey." src="docs/diagrams/trust-light.svg">
</picture>

- No infrastructure credential is stored in GitHub. A job trades its OIDC token for a 20-minute Vault token scoped to its workflow.
- Deploy roles are bound to `refs/heads/main`, so a pull request, which runs its own copy of a workflow, can only plan.
- SSH is certificates both ways: a throwaway key signed per run, and host certificates that `ssh-cert-converge` renews every week.

## Guardrails

| Layer | Guard |
|:------|:------|
| Admission | Kyverno in Enforce mode: Pod Security Restricted plus own rules, exceptions per workload |
| Network | Cilium default deny, ingress and egress, one chart for every allow |
| Runtime | Tetragon tracing policies, observe only |
| Edge | BCP 38 anti-spoofing, RPKI, prefix filters, receive limits |
| Repository | Trivy to the Security tab, gitleaks, shellcheck, actionlint, codespell |
| Access | SSH certificates from Vault, no static keys; the NAS takes YubiKeys only |

---

MIT (c) 2024-2026 Finn Paul Lippok. See [LICENSE](LICENSE).
