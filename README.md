# Homelab Setup
[![Pi4 - Deploy Docker Compose](https://github.com/FinnPL/Homelab-Setup/actions/workflows/pi4-deploy.yml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/pi4-deploy.yml)
[![Docker Compose Syntax Check](https://github.com/FinnPL/Homelab-Setup/actions/workflows/docker-syntax.yml/badge.svg)](https://github.com/FinnPL/Homelab-Setup/actions/workflows/docker-syntax.yml)

This repository contains the configuration files for my multi-site homelab setup, featuring automated CI/CD deployment, comprehensive monitoring, and networking.

## Network Architecture
![NWD](https://github.com/user-attachments/assets/5e6225d0-8305-421c-8ee2-33f057eb3ace)

### Sites Overview
The homelab consists of two geographically separated sites connected via VPN:

#### **Vieta Site** (Primary)
- **Pi4**: Main orchestration node running Docker services
- **Apollo NAS**: Primary storage and backup system

#### **Minerva Site** (Secondary)  
- **Pi3**: Secondary node for monitoring and services
- **Zeus NAS**: Secondary storage with synchronization to Apollo

### Network Segmentation
Each site implements a dual-VLAN architecture:

- **Default VLAN**: Standard network for general devices
- **Athena VLAN**: Dedicated homelab network for all infrastructure services

#### Security Model
- **VPN Tunnel**: Secure connection between Athena VLANs across sites
- **NAS Synchronization**: Automated data replication between Apollo and Zeus
- **Firewall Enforcement**: Access to Athena network from Default VLAN is **exclusively** through Traefik reverse proxy
- **Zero Trust**: No direct access to homelab services bypassing the proxy

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

### Data Collection & Exporters
| Service | Target | Port | Metrics |
|---------|--------|------|---------|
| **Node Exporter** | Pi4 System Metrics | :9100 | CPU, Memory, Disk, Network |
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
The setup now uses **environment variable substitution** for configuration files that don't natively support `.env` files. This approach provides better security and flexibility.

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
The repository includes GitHub Actions for automated deployment.  
**Note:** To use this method, you must install a custom GitHub Actions runner on your target machine.  
Additionally, add all required environment variables as GitHub repository secrets.

1. **Fork the repository**
2. **Install a custom GitHub Actions runner** on your deployment target
3. **Configure GitHub Secrets** with all required environment variables
4. **Push to main branch** – deployment happens automatically

#### Option 2: Manual Deployment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/FinnPL/NoStar.git
   cd NoStar/src/Pi4
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
