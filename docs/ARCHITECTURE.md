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
* **Nginx Proxy Manager:** The sole perimeter ingress gateway binding host ports 80 and 443. It handles SSL termination via Let's Encrypt and routes plain HTTP across isolated Docker bridge networks to backend containers (injecting `X-Forwarded-Proto: https`). Terminating encryption at the edge saves valuable ARM CPU cycles by avoiding redundant internal TLS handshakes, while the UXG-Fiber router strictly blocks external port 80 at the hardware firewall.

* **Pihole:** Network-wide ad-blocker and DNS sinkhole. Upstream recursive resolution is offloaded to Cloudflare (`1.1.1.1`) rather than running a full local recursive resolver (such as Unbound), minimizing continuous memory and CPU overhead on the Pi.

### Tier 2: State & Secrets
* **HashiCorp Vault:** Dedicated exclusively to managing secrets for the production application deployments. For homelab stability, this vault integration utilizes **static credentials**. Vault is configured with **GCP KMS Auto-Unseal**, allowing it to authenticate with Google Cloud via a strict IAM Service Account to automatically decrypt its Master Key and unseal itself on container initialization without any manual intervention.

### Tier 3: Databases & Caching
The data layer utilizes a dedicated `database` Docker network to isolate traffic from public ingress.
* **PostgreSQL:** The centralized relational database. Rather than spinning up individual database containers for each app, this single highly-optimized instance serves all workloads. Automation scripts (`01-init-users.sh`) dynamically provision isolated catalogs and user roles for production applications (Portfolio Website, Silicon Valley Trail, Country Trivia, Prop & Ferry). Sharing a single optimized engine saves over 600MB of idle RAM versus running four separate database containers. PostgreSQL environment variables are strictly managed using the `POSTGRES_SECRETS` naming convention to eliminate magic variables and ensure explicit secret injection.

* **Redis:** The centralized high-speed caching layer, configured with an absolute memory ceiling of `256MB` and an `allkeys-lru` eviction policy. Persistence is intentionally disabled (`--save ""` and `--appendonly no`), treating Redis as a purely ephemeral in-memory cache to eliminate flash storage write thrashing and prevent memory spikes from background snapshot forks. Applications adhere to the **Cache-Aside pattern**, keeping PostgreSQL as the authoritative source of truth.

* **pgAdmin:** Web-based UI for manual database administration.

### Tier 4: CI/CD & Observability Pipeline (100% FOSS)
This tier forms the backbone of the operational lifecycle. It is built entirely on Free and Open Source Software (FOSS) to deliver enterprise-grade deployment and monitoring capabilities at zero licensing cost:
* **GitHub Actions (Centralized Orchestrator & Edge Runners):** The central CI/CD automation engine. Rather than running uncoordinated cron schedules across separate repositories, a centralized **Master Orchestrator Workflow** (`deploy-orchestrator.yml`) runs on a single scheduled trigger (`07:30 UTC` / `3:30 AM EDT` / `2:30 AM EST`) with exponential-backoff dispatch retries and timestamp-filtered run polling to sequentially dispatch and monitor deployment checks and data generation across all 4 application repositories. Self-hosted edge runners (`pi-portfolio`, `pi-svt`, `pi-prop-ferry`, `pi-trivia`) run natively as **sibling containers** by mounting `/var/run/docker.sock` directly rather than running Docker-in-Docker (DinD). This avoids heavy virtualization and storage driver overhead while enforcing isolation through ephemeral runner containers (`EPHEMERAL: "true"`) and least-privilege GitHub App authentication.

* **Prometheus & Grafana (Observability):** The metrics collection and visualization stack. Prometheus scrapes time-series metrics from the host (Node Exporter), containers (cAdvisor), and databases (Postgres Exporter), rendering them onto custom Grafana dashboards.

* **Alertmanager:** Integrated with Discord webhooks natively to provide real-time alerts for critical infrastructure warnings (e.g., High Memory, Service Down).

* **UptimeRobot (Black-Box Monitoring):** An external monitoring service used to probe the public-facing endpoints (e.g., `rajivwallace.com`, `prop-ferry.rajivwallace.com`) every 5 minutes. This solves the inherent Single Point of Failure (SPoF) of hosting the monitoring stack on the same bare-metal node as the applications; if the Raspberry Pi loses power or internet connectivity, UptimeRobot provides the critical "Service Down" email and Discord alerts that an offline internal Alertmanager cannot send.

* **Watchtower:** Automates the lifecycle of base images, polling for upstream updates to containerized services and executing zero-downtime rolling restarts, immediately notifying Discord of the updated container digests.

* **UniFi Controller:** Manages VLANs, VPNs, and firewall rules across local UniFi networking gear.

---

## ⚖️ Architectural Decisions & Tradeoffs Matrix

| Design Area | Rationale | Tradeoff Accepted | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **Multi-Tenant Postgres vs. Isolated DB Containers** | Maximizes host memory efficiency (~150MB RSS for 1 engine vs. 600MB+ for 4 distinct instances). | Shared failure domain and resource competition during queries. | Automated weekly logical dumps (`pg_dumpall`), connection pooling, and separate databases/users per app. |
| **Volatile Redis Cache (`--save ""` / no AOF)** | Prevents flash drive wear and eliminates `fork()` memory doubling during background snapshots. | Cache contents are volatile and lost on restart. | Strict **Cache-Aside** design where PostgreSQL holds authoritative data and cache misses seamlessly repopulate. |
| **Edge Sibling Containers vs. Docker-in-Docker** | High build performance and low memory overhead by issuing commands directly to host Docker daemon. | Runner container mounts `/var/run/docker.sock`, giving it daemon access. | Ephemeral runner lifecycle (`EPHEMERAL: true`), dedicated non-root runner contexts, and fine-grained GitHub App tokens. |
| **Edge TLS Termination vs. Mutual TLS (mTLS)** | Minimizes cryptographic CPU overhead across internal ARM microservice calls. | Inter-container traffic on internal Docker bridge networks is plaintext HTTP. | Strict Docker network isolation (`core`, `apps`, `database`, `monitoring`) preventing cross-tier snooping. |
| **Sequential vs. Concurrent Deployment Pipelines** | Eliminates CPU contention, image-pull race conditions, and network spikes on edge node. | Total CI/CD deployment execution window is longer across all repos. | Scheduled during off-peak hours (03:30 AM EDT / 07:30 UTC) when zero interactive traffic exists. |

---

## ⏰ Operational Lifecycle & Maintenance Timeline

To guarantee high availability and prevent resource contention on the Raspberry Pi 4B (8GB RAM), the entire homelab maintenance and CI/CD lifecycle is strictly sequenced during off-peak night hours:

| Time (EDT) | Time (UTC) | Layer / Service | Operational Task | Rationale |
| :--- | :--- | :--- | :--- | :--- |
| **12:00 AM** *(Mon)* | 04:00 UTC *(Mon)* | Target Node (Root Cron) | Encrypted Volume & DB Backup (`backup_volumes.sh`) | Runs before container updates so backup captures pristine daily state. |
| **1:00 AM** *(Daily)* | 05:00 UTC *(Daily)* | Global Watchtower | Core Infrastructure & GHA Runner Image Updates | Refreshes and restarts runner containers *before* deployment checks fire. |
| **1:30 AM** *(Daily)* | 05:30 UTC *(Daily)* | UniFi Watchtower | UniFi Controller Image Monitoring | Scans UniFi stack for new upstream releases. |
| **3:30 AM** *(Daily)* | 07:30 UTC *(Daily)* | Central GHA Orchestrator (`homelab-iac`) | Sequential Application Deployments & Health Checks | Runs on fresh, idle runners. Sequentially dispatches Portfolio $\rightarrow$ SVT $\rightarrow$ Prop & Ferry $\rightarrow$ Country Trivia $\rightarrow$ AI Data Generation. |
| **9:00 AM** *(Mon)* | 13:00 UTC *(Mon)* | Dependabot | Weekly npm & uv dependency scan & grouped PR creation | Evaluated during morning business hours for active review. |