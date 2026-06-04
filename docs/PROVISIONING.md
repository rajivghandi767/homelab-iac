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