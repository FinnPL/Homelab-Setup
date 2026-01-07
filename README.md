<div align="center">
   
# Homelab Setup
   
[![Pi4 - Deploy Docker Compose](https://github.com/FinnPL/Homelab-Setup/actions/workflows/pi4-deploy.yml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/pi4-deploy.yml)
[![Pi3 - Deploy Docker Compose](https://github.com/FinnPL/Homelab-Setup/actions/workflows/pi3-deploy.yml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/pi3-deploy.yml)
[![Docker Compose Syntax Check](https://github.com/FinnPL/Homelab-Setup/actions/workflows/docker-syntax.yml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/docker-syntax.yml)

This repository contains the Terraform and Docker configuration for my multi-site homelab setup, featuring automated CI/CD deployment, comprehensive monitoring, and networking.
</div>

![NWD](https://github.com/user-attachments/assets/5e6225d0-8305-421c-8ee2-33f057eb3ace)


## Sites Overview
The homelab consists of two geographically separated sites connected via VPN:

<table width="100%">
  <tr>
    <th width="50%" align="center">Vieta Site (Primary)</th>
    <th width="50%" align="center">Minerva Site (Secondary)</th>
  </tr>
  <tr>
    <td valign="top">
      <ul>
        <li><strong>Pi4:</strong> Main orchestration node running Docker services</li>
        <li><strong>Apollo NAS:</strong> Primary storage and backup system</li>
      </ul>
    </td>
    <td valign="top">
      <ul>
        <li><strong>Pi3:</strong> Secondary node for monitoring and services</li>
        <li><strong>Zeus NAS:</strong> Secondary storage with synchronization to Apollo</li>
      </ul>
    </td>
  </tr>
</table>

> [!NOTE]
> <img align="right" width="255" height="315" alt="rack-plan" src="https://github.com/user-attachments/assets/32db0ecd-c6e9-4bf9-8fc1-1621b8900dbb" />
> Long-term direction: migrate away from Docker Compose and run services via Helm charts on a Talos-based Kubernetes cluster (RPis), with the control plane hosted on an Intel NUC running Proxmox.
> 
> Future plans for Vieta Site include a 10-inch desktop rack equipped with custom 3D-printed mounting brackets to organize the hardware.
> <br clear="right" />

## Network & Security
Each site implements a dual-VLAN architecture to separate domestic devices from infrastructure.

| VLAN Name | Type | Description |
| :--- | :--- | :--- |
| **Default** | Standard | General devices (Phones, Laptops, IoT) |
| **Athena** | Infrastructure | Dedicated homelab network for all services |

### Security Model
* **VPN Tunnel:** Secure connection between Athena VLANs across sites.
* **NAS Sync:** Automated data replication between *Apollo* and *Zeus*.
* **Firewall Enforcement:** Access to Athena network from Default VLAN is exclusively through Traefik reverse proxy. No direct access to homelab services bypassing the proxy

## Infrastructure as Code
The homelab utilizes Terraform as the Infrastructure as Code (IaC) principles through Terraform to ensure a declarative, reproducible, and version-controlled foundation for the entire network and server stack.

Terraform is organized into numbered layers (each with its own backend state).

- `00-global/`: Shared Terraform foundation (remote state backend, base provider config)
- `01-network/`: UniFi network state (VLANs, DHCP reservations, port profiles) + Cloudflare DNS
- `02-infrastructure/`: Proxmox + Talos bootstrap for my Kubernetes homelab *(planned / not implemented yet)*
- `03-services/`: Helm charts deployed onto the cluster *(planned / not implemented yet)*

## Services Architecture

### Core Infrastructure
| Service | Description | URL | Purpose |
|---------|-------------|-----|---------|
| **Traefik** | Reverse Proxy & Load Balancer | All `*.lippok.dev` | SSL termination, routing, authentication |
| **Portainer** | Docker Management | `port.lippok.dev` | Container orchestration and monitoring |

### Monitoring & Observability Stack
| Service | Description | URL | Metrics Port |
|---------|-------------|-----|--------------|
| **Prometheus** | Metrics Collection | `prometheus.lippok.dev` | :9090 |
| **Grafana** | Data Visualization | `grafana.lippok.dev` | :3000 |
| **Alertmanager** | Alert Management | `alerts.lippok.dev` | :9093 |
| **Gatus** | Uptime Monitoring | `gatus.lippok.dev` | :8080 |

### Grafana Dashboard Overview
<img width="2495" height="1198" alt="Grafana Dashboard" src="https://github.com/user-attachments/assets/43318626-acb7-4344-9612-efcbe777f76f" />


### Data Collection & Exporters
| Service | Target | Port | Metrics |
|---------|--------|------|---------|
| **Node Exporter** | Pi4 System Metrics | :9100 | CPU, Memory, Disk, Network |
| **Node Exporter (Pi3)** | Pi3 System Metrics | :9100 | CPU, Memory, Disk, Network |
| **cAdvisor** | Docker Container Metrics | :8080 | Container resources and performance |
| **UnPoller (Local)** | UniFi Controller (10.10.0.1) | :9130 | Local network statistics |
| **UnPoller (Remote)** | UniFi Controller (10.0.0.1) | :9131 | Remote network statistics |
| **Mailcow Exporter** | Mail Server (mail.lippok.eu) | :9099 | Email service metrics |
| **FritzBox Exporter** | Router (192.168.178.1) | :9787 | ISP connection and router stats |

### User Interface & Dashboard
| Service | Description | URL | Features |
|---------|-------------|-----|----------|
| **Homepage** | Unified Dashboard | `olympus.lippok.dev` | Service status, weather, quick access |

## Configuration & Setup

### Prerequisites
- Docker and Docker Compose installed
- `apache2-utils` for password hashing
- `envsubst` for template processing

### Environment Variables
The setup uses **environment variable substitution** for configuration files that don't natively support `.env` files.

#### Required Environment Variables
Create a `.env` file in `src/Pi4/` with the following variables:

```bash
# Traefik Authentication
TRAEFIK_USER=admin
TRAEFIK_PASSWORD=<hashed_password>
TRAEFIK_PASSWORD_UNHASHED=<plain_password>

# Cloudflare DNS (for Let's Encrypt)
CLOUDFLARE_EMAIL=your-email@domain.com
CF_DNS_API_TOKEN=your_cloudflare_token

# Container Passwords
PORTAINER_PASSWORD=<hashed_password>
GRAFANA_ADMIN_PASSWORD=your_secure_password

# API Keys & Integration
HOMEPAGE_VAR_OPENWEATHERMAP_API_KEY=your_weather_api_key
HOMEPAGE_VAR_MAILCOW_API_KEY=your_mailcow_api_key
HOMEPAGE_VAR_PORTAINER_API_KEY=your_portainer_api_key

# UniFi Credentials
HOMEPAGE_VAR_UNIFI_USER=unifi_username
HOMEPAGE_VAR_UNIFI_PASSWORD=unifi_password

# Router Credentials
FRITZBOX_USERNAME=fritz_username
FRITZBOX_PASSWORD=fritz_password

# Notification Webhooks
DISCORD_WEBHOOK_URL=your_discord_webhook_url

# Tailscale Configuration
TAILSCALE_AUTHKEY=your_tailscale_auth_key
```

### Password Hashing
Generate hashed passwords for Traefik and Portainer:

```bash
# Install apache2-utils if not present
sudo apt-get install apache2-utils

# Generate password hash for Traefik/Portainer
htpasswd -nb admin your_password
# Copy the full output for TRAEFIK_PASSWORD

# For Portainer, extract just the hash part
htpasswd -nb -B admin your_password | cut -d ":" -f 2
# Copy the hash for PORTAINER_PASSWORD
```

### Template Processing
The setup uses `.template` files that are processed with `envsubst` to inject environment variables:

- `traefik.yml.template` → `traefik.yml`
- `prometheus.yml.template` → `prometheus.yml`  
- `alertmanager.yml.template` → `alertmanager.yml`

### Installation Methods

#### Option 1: Automated CI/CD (Recommended)
The repository includes GitHub Actions for automated deployment of both Pi4 and Pi3 sites.  
**Note:** To use this method, you must install custom GitHub Actions runners on your target machines.  
Additionally, add all required environment variables as GitHub repository secrets.

1. **Fork the repository**
2. **Install a custom GitHub Actions runner** on your deployment target
3. **Configure GitHub Secrets** with all required environment variables
4. **Push to main branch** – deployment happens automatically

#### Option 2: Manual Deployment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/FinnPL/Homelab-Setup.git
   cd Homelab-Setup/src/Pi4
   ```

2. **Create and configure `.env` file:**
   ```bash
   nano .env
   # Add all required environment variables
   ```

3. **Generate configuration files from templates:**
   ```bash
   # Export environment variables
   set -a && source .env && set +a
   
   # Process templates
   envsubst < traefik/traefik.yml.template > traefik/traefik.yml
   envsubst < prometheus/prometheus.yml.template > prometheus/prometheus.yml
   envsubst < alertmanager/alertmanager.yml.template > alertmanager/alertmanager.yml
   ```

4. **Deploy the stack:**
   ```bash
   docker compose up -d
   ```

5. **Configure Portainer API:**
   - Access Portainer at `https://port.lippok.dev`
   - Navigate to **User settings → API tokens**
   - Generate and copy the API key
   - Add `HOMEPAGE_VAR_PORTAINER_API_KEY` to `.env`
   - Restart homepage: `docker compose restart homepage`
