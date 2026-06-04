# Homelab Infrastructure as Code (IaC)

Welcome to my infrastructure repository. This project is a fully automated, secure bare-metal homelab built from the ground up using Infrastructure as Code (IaC). It acts as the central hub for hosting my personal applications in a true production-grade environment. I built this to bridge the gap between development and operations, applying real-world DevOps practices, zero-data-loss disaster recovery, and declarative configuration management to my own workloads.

## 🎯 Project Intent & Impact

This project was built to transition a manual home networking setup into a resilient, production-ready environment. Key achievements include:
* **100% Declarative Infrastructure:** Eliminated configuration drift by managing 8+ containerized backend services, DNS records, and cloud storage buckets using **Ansible** and **Terraform**.

* **Zero-Trust Disaster Recovery:** Engineered an automated, encrypted weekly backup pipeline using `pigz`, GPG, and Google Cloud Storage (GCS) that allows for full bare-metal recovery with zero data loss.

* **FinOps & Resource Efficiency:** Architected an enterprise-grade CI/CD and observability pipeline using 100% Free and Open Source Software (FOSS). The entire cloud footprint operates at near-zero cost (~$0.05 to $1.00/month for GCS encrypted backups, and ~$12/year for the custom domain).

* **End-to-End Event Alerting:** Integrated comprehensive Discord webhooks across the entire operational lifecycle. Real-time notifications (Success/Failure) are dispatched for CI/CD builds, app deployments, base container updates, and automated remote backups.

## 🚀 Hosted Production Workloads

This infrastructure serves as the live production host for my active full-stack development portfolio. Each application lives in its own dedicated repository and is dynamically provisioned into the environment via the Jenkins CI/CD pipeline:

*   **Country Trivia Game:** A full-stack Django/React application integrating Gemini AI to dynamically generate trivia questions and facts. It utilizes custom REST APIs and dedicated Jenkins pipelines for continuous data generation.
    *   [Play Live](https://trivia.rajivwallace.com) | [Source Code](https://github.com/rajivghandi767/country-trivia-web)

*   **Prop & Ferry:** A travel search and logistics platform using Django and TypeScript. It utilizes isolated Jenkins pipelines for scheduled, asynchronous web scraping and route data aggregation, decoupling heavy tasks from the main application thread.
    *   [Live Site](https://prop-ferry.rajivwallace.com) | [Source Code](https://github.com/rajivghandi767/prop-and-ferry)

*   **Silicon Valley Trail:** A state-driven web game powered by a custom Django event engine that orchestrates location tracking, weather systems, and player actions, consumed by a Vite/React frontend.
    *   [Play Live](https://svt.rajivwallace.com) | [Source Code](https://github.com/rajivghandi767/silicon-valley-trail)

*   **Portfolio Website:** A containerized Django/React application featuring a custom backend CMS for blog posts, project showcases, and automated contact routing.
    *   [Live Site](https://rajivwallace.com) | [Source Code](https://github.com/rajivghandi767/portfolio-website)

## 💻 Environment Topology

This infrastructure strictly enforces a separation of concerns using a dual-node architecture model:

* **Control Node (Macbook):** The secure local workstation where development, secret management (via Ansible Vault), and the execution of Terraform/Ansible commands take place. No raw secrets are ever committed to version control (`.gitignore` enforces this).

* **Target Node (Raspberry Pi 4B w/ 8GB RAM):** The bare-metal production server running a headless DietPi/Debian OS. This node executes the containerized workloads and operates on a principle of ephemeral state.

## 📂 Directory Structure

The repository is organized by lifecycle boundaries to prevent state drift and secure secret injection:

```text
📦 homelab-iac/
├── 🗄️ ansible/                 # Core configuration management
│   ├── 🔐 group_vars/          # Encrypted Vault variables and configs
│   ├── 📋 inventory/           # Target Node definitions
│   ├── 🚀 deploy.yml           # Orchestrates the service DAG
│   ├── 🧱 foundation.yml       # Provisions base OS and dependencies
│   └── 🚑 restore.yml          # Zero-trust disaster recovery pipeline
├── 📚 docs/                    # Architectural and operational documentation
├── 📜 scripts/                 # Bash utilities (e.g., backup_volumes.sh)
├── 🐳 services/                # Docker Compose definitions (The Stack)
│   ├── 📦 apps/                # External application workloads
│   ├── ⚙️ core/                # Jenkins, Nginx, Pihole, Vault, UniFi
│   ├── 🗃️ database/            # Postgres, pgAdmin, Redis
│   ├── 🍿 media/               # Jellyfin
│   └── 📈 monitoring/          # Prometheus, Alertmanager, Watchtower
├── ☁️ terraform/               # Cloud provisioning (GCS, Cloudflare)
└── 🛠️ vars/                    # Jenkins shared libraries (Groovy)
```

## 🚨 IN CASE OF EMERGENCY (ICE)
If the primary server has catastrophically failed or the Control Node is lost, proceed directly to the **[Disaster Recovery & Restores](docs/DISASTER_RECOVERY.md)** guide for instructions on bootstrapping a new Control Node and executing a zero-data-loss recovery.

## 📖 Documentation Navigation

* **[Architecture & Services Design](docs/ARCHITECTURE.md)** - Details the network segmentation, traffic ingress, and service layers.

* **[Provisioning Guide](docs/PROVISIONING.md)** - Step-by-step instructions for installing dependencies, authenticating Terraform, and deploying a fresh environment.

* **[Disaster Recovery & Restores](docs/DISASTER_RECOVERY.md)** - Emergency playbooks for restoring the environment, including the Total Loss Protocol.