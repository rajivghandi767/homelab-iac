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
                        │   4 Repos   │ │ GHA Runners │ │ Prometheus  │
                        │             │ │   & Vault   │ │  & Grafana  │
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

To enforce a zero-trust security posture and isolate experimental environments from daily operations, the network is segmented via strict VLANs and managed firewall policies:

* **Management/Default VLAN:** Strictly routes internet traffic and isolates the core Ubiquiti networking hardware. No personal, guest, or compute workloads reside here.

* **Personal VLAN:** The primary residential network for trusted, resident-owned personal devices. Operating under an administrative posture, this VLAN has authorized cross-VLAN routing permissions to initiate traffic to all other subnets for management purposes.

* **Work VLAN:** A dedicated subnet for professional/corporate devices. It is securely firewalled to ensure complete compute stability, bandwidth prioritization, and total isolation from other residential subnets.

* **Homelab VLAN:** The isolated environment hosting the Raspberry Pi bare-metal server and containerized infrastructure. Ingress is tightly restricted via Nginx Proxy Manager, and it is strictly firewalled to prevent any unauthorized lateral movement or traffic origination to personal or work subnets.

* **IoT VLAN:** A completely isolated subnet reserved strictly for smart home and Internet of Things appliances. It is blocked from communicating with any other internal network, preventing vulnerable smart devices from acting as a lateral attack vector.

* **Guest VLAN:** A sandboxed network strictly for temporary visitors and non-resident devices. It grants immediate internet access but enforces isolation rules that block cross-talk to all local subnets.

* **WireGuard VPN:** To ensure secure remote access when traveling or working remotely, a WireGuard VPN is configured directly on the UXG-Fiber gateway. This securely tunnels remote devices into the trusted VLAN layers without exposing internal services to the broader public internet.

## 🏗️ Layered Orchestration (The Ansible DAG)

The `deploy.yml` playbook orchestrates the stack in the following tiers:

### Tier 1: Network & Ingress
* **Nginx Proxy Manager:** Handles SSL termination and reverse proxy routing to internal Docker networks.

* **Pihole:** Operates strictly as a network-wide ad-blocker (DNS resolution is deliberately offloaded to Cloudflare).

### Tier 2: State & Secrets
* **HashiCorp Vault:** Dedicated exclusively to managing secrets for the production application deployments. For homelab stability, this vault integration utilizes **static credentials**. Vault is configured with **GCP KMS Auto-Unseal**, allowing it to authenticate with Google Cloud via a strict IAM Service Account to automatically decrypt its Master Key and unseal itself on container initialization without any manual intervention.

### Tier 3: Databases & Caching
The data layer utilizes a dedicated `database` Docker network to isolate traffic from public ingress.
* **PostgreSQL:** The centralized relational database. Rather than spinning up individual database containers for each app, this single highly-optimized instance serves all workloads. Automation scripts (`01-init-users.sh`) dynamically provision isolated catalogs and user roles for production applications (Portfolio Website, Silicon Valley Trail, Country Trivia, Prop & Ferry). PostgreSQL environment variables are strictly managed using the `POSTGRES_SECRETS` naming convention to eliminate magic variables and ensure explicit secret injection.

* **Redis:** The centralized high-speed caching layer. A single lightweight container handles caching for all applications simultaneously, configured with an absolute memory ceiling of `256MB` and an `allkeys-lru` eviction policy to prevent OOM cascading failures.

* **pgAdmin:** Web-based UI for manual database administration.

### Tier 4: CI/CD & Observability Pipeline (100% FOSS)
This tier forms the backbone of the operational lifecycle. It is built entirely on Free and Open Source Software (FOSS) to deliver enterprise-grade deployment and monitoring capabilities at zero licensing cost:
* **GitHub Actions (Centralized Orchestrator & Edge Runners):** The central CI/CD automation engine. Rather than running uncoordinated cron schedules across separate repositories, a centralized **Master Orchestrator Workflow** (`deploy-orchestrator.yml`) runs on a single scheduled trigger (`06:15 UTC` / `2:15 AM EDT`) to sequentially dispatch and monitor deployment checks and data generation across all 4 application repositories. Self-hosted edge runners (`pi-portfolio`, `pi-svt`, `pi-prop-ferry`, `pi-trivia`) execute the jobs natively on the Raspberry Pi without queue congestion or concurrent image pull locks.

* **Prometheus & Grafana (Observability):** The metrics collection and visualization stack. Prometheus scrapes time-series metrics from the host (Node Exporter), containers (cAdvisor), and databases (Postgres Exporter), rendering them onto custom Grafana dashboards.

* **Alertmanager:** Integrated with Discord webhooks natively to provide real-time alerts for critical infrastructure warnings (e.g., High Memory, Service Down).

* **Watchtower:** Automates the lifecycle of base images, polling for upstream updates to containerized services and executing zero-downtime rolling restarts, immediately notifying Discord of the updated container digests.

* **UniFi Controller:** Manages VLANs, VPNs, and firewall rules across local UniFi networking gear.

---

## ⏰ Operational Lifecycle & Maintenance Timeline

To guarantee high availability and prevent resource contention on the Raspberry Pi 4B (8GB RAM), the entire homelab maintenance and CI/CD lifecycle is strictly sequenced during off-peak night hours:

| Time (EDT) | Time (UTC) | Layer / Service | Operational Task | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **12:00 AM** *(Mon)* | 04:00 UTC *(Mon)* | Target Node (Root Cron) | Encrypted Volume & DB Backup (`backup_volumes.sh`) | Runs before container updates so backup captures pristine daily state. |
| **1:00 AM** *(Daily)* | 05:00 UTC *(Daily)* | Global Watchtower | Core Infrastructure & GHA Runner Image Updates | Refreshes and restarts runner containers *before* deployment checks fire. |
| **1:30 AM** *(Daily)* | 05:30 UTC *(Daily)* | UniFi Watchtower | UniFi Controller Image Monitoring | Scans UniFi stack for new upstream releases. |
| **2:15 AM** *(Daily)* | 06:15 UTC *(Daily)* | Central GHA Orchestrator (`homelab-iac`) | Sequential Application Deployments & Health Checks | Runs on fresh, idle runners. Sequentially dispatches Portfolio $\rightarrow$ SVT $\rightarrow$ Prop & Ferry $\rightarrow$ Country Trivia $\rightarrow$ AI Data Generation. |
| **9:00 AM** *(Mon)* | 13:00 UTC *(Mon)* | Dependabot | Weekly npm dependency scan & grouped PR creation | Evaluated during morning business hours for active review. |