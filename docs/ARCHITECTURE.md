# Architecture & Services Design

The Target Node runs highly available backend services structured in a strict Directed Acyclic Graph (DAG) during provisioning. This ensures foundational dependencies are fully initialized before downstream applications boot.

## 🌐 Ingress & Microservices Traffic Flow

```text
                                      [ Public Internet ]
                                              │
                                        (HTTPS / 443)
                                              ▼
                       ┌───────────────────────────────────────────────┐
                       │            Cloudflare (DNS/Proxy)             │
                       └───────────────────────┬───────────────────────┘
                                       (Port Forwarding)
                                               ▼
                       ┌───────────────────────────────────────────────┐
                       │               UXG-Fiber Gateway               │
                       └───────────────────────┬───────────────────────┘
                                        (VLAN Routing)
                                               ▼
    =========================================================================================
                               [ Homelab Subnet / Target Node ]

                       ┌───────────────────────────────────────────────┐
                       │              Nginx Proxy Manager              │
                       │           (SSL Termination/Routing)           │
                       └───────┬───────────────┬───────────────┬───────┘
                               │               │               │
                               ▼               ▼               ▼
                        ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
                        │    Apps     │ │    Core     │ │   Monitor   │
                        │   4 Repos   │ │  Jenkins &  │ │ Prometheus  │
                        │             │ │    Vault    │ │  & Grafana  │
                        └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
                               │               │               │
                               ▼               ▼               ▼
                       ┌───────┴───────────────┴───────────────┴───────┐
                       │           Isolated Database Network           │
                       │             (PostgreSQL & Redis)              │
                       └───────────────────────────────────────────────┘
    =========================================================================================
```

## 🛡️ Physical Networking & Network Segmentation

The homelab's physical foundation is built on Ubiquiti UniFi infrastructure, featuring a UXG-Fiber gateway, a U7 Pro Wall access point, and a Switch Flex Mini 2.5G for high-throughput backhaul. 

To enforce a zero-trust security posture and isolate experimental environments from daily operations, the network is strictly segmented via VLANs and managed firewall policies:

* **Management/Default VLAN:** Strictly routes internet traffic and isolates the core Ubiquiti networking hardware. No personal or compute devices reside here.

* **Homelab VLAN:** The dedicated subnet for the Raspberry Pi bare-metal server and containerized infrastructure. Ingress is tightly controlled, and it is strictly firewalled off from personal devices.

* **IoT & Guest VLANs:** Completely isolated subnets with no cross-talk allowed to the Homelab or Work networks, preventing vulnerable smart devices from acting as an attack vector.

* **Personal & Work VLANs:** Dedicated networks for daily operations and remote work, ensuring compute stability and bandwidth prioritization.

* **WireGuard VPN:** To ensure secure remote access when traveling or away from home, a WireGuard VPN is configured directly on the UXG-Fiber gateway. This tunnels remote devices into the secure management/homelab VLANs without exposing internal services to the broader public internet. This VPN is also used for safety/security, when connected to external wired or wireless networks (e.g. hotels, coffee shops, etc).

## 🏗️ Layered Orchestration (The Ansible DAG)

The `deploy.yml` playbook orchestrates the stack in the following tiers:

### Tier 1: Network & Ingress
* **Cloudflare:** Proxies all incoming public traffic and dynamically handles all **local DNS** resolution for the homelab.
* **Nginx Proxy Manager:** Handles SSL termination and reverse proxy routing to internal Docker networks.
* **Pihole:** Operates strictly as a network-wide ad-blocker (DNS resolution is deliberately offloaded to Cloudflare).

### Tier 2: State & Secrets
Secret management is split across two domains to separate infrastructure provisioning from application runtime:
* **GCP Secret Manager:** Dynamically handles the injection of secrets exclusively for **Terraform** infrastructure provisioning (e.g., GCS buckets, Cloudflare DNS records).
* **HashiCorp Vault:** Dedicated exclusively to managing secrets for the production application deployments. For homelab stability, this vault integration utilizes **static credentials**. A Jenkins pipeline (`Unseal-Vault.Jenkinsfile`) is available to automatically unseal the vault using injected unseal keys. Production CI/CD pipelines utilize this Jenkinsfile to dynamically check if the vault is sealed or unsealed, and unseal it if necessary.

### Tier 3: Databases & Caching
The data layer utilizes a dedicated `database` Docker network to isolate traffic from public ingress.
* **PostgreSQL:** The core relational database. Automation scripts (`01-init-users.sh`) dynamically provision isolated catalogs and user roles for production applications (Portfolio, SVT, Trivia, Prop & Ferry). PostgreSQL environment variables are strictly managed using the `POSTGRES_SECRETS` naming convention to eliminate magic variables and ensure explicit secret injection.

* **Redis:** High-speed caching layer for application state.

* **pgAdmin:** Web-based UI for manual database administration.

### Tier 4: CI/CD & Observability Pipeline (100% FOSS)
This tier forms the backbone of the operational lifecycle. It is built entirely on Free and Open Source Software (FOSS) to deliver enterprise-grade deployment and monitoring capabilities at zero licensing cost:
* **Jenkins (Continuous Integration / Deployment):** The central CI/CD automation engine. Jenkins dynamically pulls from external application repositories, builds the Docker images, and deploys the containers into the isolated networks. It dispatches real-time success or failure alerts directly to Discord upon pipeline completion.

* **Prometheus & Grafana (Observability):** The metrics collection and visualization stack. Prometheus scrapes time-series metrics from the host (Node Exporter), containers (cAdvisor), and databases (Postgres Exporter), rendering them onto custom Grafana dashboards.

* **Alertmanager:** Integrated with Discord webhooks via Groovy scripts (`notifyDiscord.groovy`) to provide real-time alerts for critical pipeline failures or infrastructure warnings (e.g., High Memory, Service Down).

* **Watchtower:** Automates the lifecycle of base images, polling for upstream updates to containerized services and executing zero-downtime rolling restarts, immediately notifying Discord of the updated container digests.

* **UniFi Controller:** Manages VLANs, VPNs, and firewall rules across local UniFi networking gear.