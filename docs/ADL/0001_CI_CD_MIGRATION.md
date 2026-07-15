# Architectural Decision Record: CI/CD & Secrets Modernization

## Executive Summary
This document outlines the strategic migration of the infrastructure's Continuous Integration / Continuous Deployment (CI/CD) pipelines and Secrets Management engine. 

The objective is to deprecate the monolithic Jenkins orchestrator in favor of a decentralized, edge-executed **GitHub Actions** architecture, while simultaneously hardening HashiCorp Vault by transitioning from manual unseal processes to **GCP KMS Auto-Unseal**. This migration achieves a zero-downtime cutover while significantly reducing compute overhead, improving security isolation, and aligning the repository with modern cloud-native standards.

---

## 1. The "Why": Drivers for Change

### A. Compute Optimization at the Edge
The current infrastructure relies on a centralized Jenkins Master node running within the cluster. Jenkins is heavily reliant on the Java Virtual Machine (JVM), continuously consuming 1-2GB of RAM regardless of pipeline activity. By migrating to a **GitHub Actions Self-Hosted Runner**, the orchestrator UI and webhook management are offloaded to GitHub's cloud. The local edge node only runs a lightweight Go-based polling agent (~50MB RAM), freeing massive compute resources for actual application workloads.

### B. Security Posture & Isolation
1. **The Docker Socket Vulnerability:** To build and deploy applications, the current Jenkins container requires a direct volume mount to the host's `/var/run/docker.sock`. This effectively grants the CI/CD pipeline root-level access to the underlying Debian/Proxmox host—a major security anti-pattern. The new architecture resolves this by isolating the runner and restricting deployment execution exclusively through authenticated SSH (Principle of Least Privilege).
2. **The Disaster Recovery Paradox:** Currently, Vault unseal keys are managed manually or via CI automation. If the server experiences a catastrophic failure, recovering the unseal keys to rebuild the infrastructure creates a "chicken-and-egg" scenario. Migrating to GCP KMS Auto-Unseal entirely removes human and CI intervention from the cryptographic boot sequence.

### C. Developer Experience & IaC Evolution
Maintaining Groovy-based Jenkinsfiles and managing volatile Jenkins plugins introduces unnecessary operational overhead. Transitioning to native, declarative YAML workflows (`.github/workflows/`) provides a cleaner 1-to-1 mapping of CI/CD intent (Build, Deploy, Cron) and serves as the foundational prerequisite for an eventual transition to Kubernetes and GitOps (ArgoCD).

---

## 2. The "How": Target Architecture

### Secrets Management: Vault + GCP KMS
Vault will be reconfigured to delegate the decryption of its Master Key to Google Cloud Key Management Service (KMS). Upon container initialization, Vault will authenticate with GCP via a strict IAM Service Account, decrypt the key, and instantly unseal itself. This eliminates the need for the legacy `Unseal-Vault.Jenkinsfile`.

### CI/CD Topology: GitHub Actions
Instead of monolithic pipelines, projects will adopt highly specific, event-driven YAML workflows:
* **`build.yml`**: Triggered on `push`. Executes unit tests and builds artifacts. Uses the ephemeral `${{ secrets.GITHUB_TOKEN }}` to publish to GHCR.
* **`deploy.yml`**: Triggered post-build. The self-hosted runner executes an SSH deployment to the target node using injected Vault AppRole credentials.
* **`cron.yml`**: Replaces legacy Jenkins schedulers (e.g., Duffel route fetching, ferry scraping) using native GitHub cron syntax.

---

## 3. Execution Strategy (Zero-Downtime Migration)

To ensure zero disruption to live applications, the migration utilizes a parallel infrastructure approach:

1. **Parallel Bootstrap:** The GitHub Actions Runner container is deployed alongside the running Jenkins instance. Both orchestrators listen concurrently.
2. **Vault Cryptographic Cutover:** GCP KMS is provisioned via Terraform. Vault is restarted into a migration state where legacy keys are provided once to wrap the master key with GCP KMS. Running applications experience zero downtime as secrets are cached in memory.
3. **Progressive Pipeline Cutover:** Projects are migrated individually. Once a GitHub Actions `.yml` workflow is validated, the corresponding Jenkins job is disabled. 
4. **Decommissioning:** Once the Jenkins dashboard is entirely idle, the container, volumes, and JVM footprint are permanently purged from the infrastructure.

---

## 4. Migration Progress Tracker

### Phase 1: Vault Modernization (GCP KMS)
- [ ] Provision GCP KMS KeyRing and CryptoKey via Terraform.
- [ ] Bind GCP Service Account to `cloudkms.cryptoKeyEncrypterDecrypter`.
- [ ] Update `vault.hcl` with the `seal "gcpckms"` configuration block.
- [ ] Execute Vault migration command.
- [ ] Validate automated unseal upon container restart.
- [ ] Purge `Unseal-Vault.Jenkinsfile` from codebase.

### Phase 2: CI/CD Infrastructure
- [ ] Deploy `github-actions-runner` container in `services/core`.
- [ ] Provision generic `github-actions` Vault AppRole (Read-Only).
- [ ] Inject `ROLE_ID`, `SECRET_ID`, and `PI_SSH_KEY` into GitHub Repository Secrets.

### Phase 3: Project Cutover
- [x] **Silicon Valley Trail:** Map `Jenkinsfile` & `Jenkinsfile.deploy` ➡️ `.github/workflows/`.
- [x] **Portfolio Website:** Map `Jenkinsfile` & `Jenkinsfile.deploy` ➡️ `.github/workflows/`.
- [x] **Country Trivia Web:** Map `Jenkinsfile`, `Jenkinsfile.deploy`, and `Jenkinsfile.data_generation` ➡️ `.github/workflows/`.
- [x] **Prop & Ferry:** Map `Jenkinsfile`, `Jenkinsfile.deploy`, `Jenkinsfile.fetch_routes`, and `Jenkinsfile.scrape_ferries` ➡️ `.github/workflows/`.

### Phase 4: Clean Up
- [x] Decommission Jenkins container and wipe associated volumes.
- [x] Update `ARCHITECTURE.md` to document the new runner topology.
- [x] Transition runners from Stateful persistent volumes to Stateless GitHub App authentication.

---

## 5. Retrospective

**Successes:**
* **Zero-Downtime Cutover:** Successfully migrated the entire infrastructure by running GitHub Actions and Jenkins in parallel during the transition.
* **GCP KMS Auto-Unseal:** Vault now boots automatically without human intervention, drastically improving our disaster recovery posture.
* **Secret Isolation:** Abstracting secrets out of GitHub via the `hashicorp/vault-action` ensures strict least-privilege for CI/CD runners.

**Challenges & Solutions:**
* **The Statefulness Trap:** Initially, the self-hosted runners were configured with 1-hour registration tokens. To prevent crash loops upon restart, we erroneously introduced state by mounting persistent volumes (`runner-cache-<project>`) to cache their `.credentials` session permanently, bypassing the ephemeral token expiration.
  * **The Problem:** This broke the fundamental cloud-native design of ephemeral runners. The cached runner instances were continually outdated, and the self-updates drastically spiked container startup times (from 3 seconds to 45 seconds). More critically, statefulness violated our goal of 100% declarative, stateless edge nodes.
  * **The True Fix (Stateless GitHub App Auth):** We completely re-architected the containers to be fully stateless and explicitly ephemeral (`EPHEMERAL: "true"`). Instead of tokens, the runners now authenticate dynamically using a **GitHub App ID and Private Key**. This completely eliminated the need for persistent volumes.
  * **Watchtower Synergy:** With runner self-updating intentionally disabled to eliminate boot latency (`DISABLE_AUTO_UPDATE: "true"`), we explicitly tagged the runners with the `com.centurylinklabs.watchtower.scope=global` label. Watchtower now seamlessly manages pulling and redeploying the newest runner images in the background, maintaining a perfect, stateless, auto-updating CI/CD pipeline.
