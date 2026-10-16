# Initial Provisioning Guide

This guide details the steps to deploy the infrastructure from scratch. It assumes you are operating from the designated **Control Node** and targeting the bare-metal **Target Node**.

## 1. Control Node Prerequisites

Ensure the Control Node has the necessary IaC binaries installed:
```bash
# MacOS / Homebrew
brew install terraform ansible gnupg
```

## 2. Infrastructure Deployment (Terraform)

Terraform is responsible for configuring Cloudflare DNS records and provisioning the Google Cloud Storage (GCS) buckets used for backups.

1. **Authenticate with GCP:** Ensure your local shell is authenticated to read from the GCP Secret Manager.
```bash
   gcloud auth application-default login
   ```
2. **Initialize and Apply:**
```bash
   cd terraform
   terraform init
   terraform plan
   terraform apply
   ```

## 3. Configuration Management (Ansible)

Ansible provisions the base OS packages on the Target Node, establishes the strict directory scaffolding, dynamically generates `.env` and other configuration files from Jinja2 templates (e.g. 'vault_token.j2'), and boots the Docker network.

1. **Populate Secrets:** Ensure `ansible/group_vars/all/secrets.yml` is populated and encrypted via `ansible-vault`. Ensure your vault password is saved locally at `~/.ansible_vault_pass`.

2. **Provision the Foundation:** This hardens the OS, installs Docker, and creates the required folder permissions via `foundation.yml`.
```bash
   cd ansible
   ansible-playbook -i inventory/hosts.ini foundation.yml
   ```
3. **Deploy the Stack:** This boots the containers in their required DAG order via `deploy.yml`.
```bash
   ansible-playbook -i inventory/hosts.ini deploy.yml
   ```

## 4. CI/CD Orchestrator & Runner Authentication (GitHub Actions)

The central deployment orchestrator workflow in `.github/workflows/deploy-orchestrator.yml` requires authentication to dispatch workflows across all application repositories:

1. **GitHub App Installation:** Ensure your dedicated GitHub App is installed across all homelab repositories (`homelab-iac`, `portfolio-website`, `silicon-valley-trail`, `prop-and-ferry`, `country-trivia-web`) with `Actions: Read and write` and `Contents: Read` permissions.
2. **Configure Repository Secrets:** Add the following repository secrets to `homelab-iac`:
   * `GH_APP_ID`: The App ID from your GitHub App settings.
   * `GH_APP_PRIVATE_KEY`: The `.pem` RSA private key generated for the App.
3. **Runner Verification:** Verify on the Target Node that self-hosted runners (`pi-portfolio`, `pi-svt`, `pi-prop-ferry`, `pi-trivia`) report online in GitHub repository settings.

---

## ⚖️ Provisioning Tradeoffs & Security Posture

* **Push Architecture vs. Server-Side Git Clones:** The Target Node is deliberately "git-less". It contains no `.git` directories and holds no GitHub Personal Access Tokens or repository SSH deployment keys.
  * *The "Why":* Ansible uses `rsync` over SSH to push rendered Jinja2 templates directly to the server. If the edge host is ever breached, an attacker cannot pivot to GitHub or inspect git commit logs for historical secrets.
  * *The Tradeoff:* The Target Node cannot autonomously pull updates; all infrastructure provisioning must be pushed from an authenticated Control Node.
* **Flash Storage Wear Mitigation:** By default, Linux on a Raspberry Pi maintains a swapfile on the boot MicroSD card.
  * *The "Why":* `foundation.yml` overrides this behavior by relocating the 4GB swapfile to `/mnt/media/swapfile` (external USB 3.2 storage) and configuring Docker's `data-root` at `/mnt/dockerdata` with strict container log rotation (`max-size: 10m`, `max-file: 3`).
  * *The Tradeoff:* Incurs wear cycles on replaceable external USB media to ensure the critical MicroSD boot OS is shielded from premature write exhaustion and root filesystem disk starvation.
* **Principle of Least Privilege Configuration (`chmod 0600`):** All sensitive templated files (`.env`, `gcp-kms.json`) pushed by Ansible are explicitly locked down to `owner: root` and `mode: 0600`. Unprivileged container processes or compromised applications cannot inspect host-level secrets.