# Disaster Recovery & Restores

This infrastructure treats the Target Node as ephemeral. In the event of total hardware failure, data loss, or corruption, the system can be fully recovered from encrypted remote GCS backups.

## 💾 Automated Backup Pipeline

A root-level cron job executes `backup_volumes.sh` daily. This pipeline ensures zero-data loss through the following mechanisms:
1. **Serialization:** Target containers are gracefully stopped while `pigz` streams a highly compressed archive of the Docker volume across multiple CPU cores.

2. **Logical Dumps:** Executes a `pg_dumpall` on the central Postgres engine to capture all application schemas and data.

3. **Encryption:** All archives are locally encrypted using GPG and a secure passphrase.

4. **Offsite Replication:** Encrypted archives are securely pushed to the Terraform-provisioned GCS bucket. 

5. **Alerting:** Pushes a final status payload (Success/Failure) directly to a dedicated Discord channel, providing daily operational peace of mind without requiring manual log audits.

---

## 🚨 Emergency Restore Scenario: The "Total Loss" Protocol

**Scenario:** The Target Node has suffered complete drive failure, AND your local Control Node (Mac) was lost, stolen, or destroyed. You are operating from a **Brand New Control Node**.

### Phase 1: Bootstrap the New Control Node
You must first recreate the control environment.
```bash
# Install required dependencies
brew install terraform ansible gnupg google-cloud-sdk
```

### Phase 2: Recover Cloud Credentials & Ansible Vault Password
Because the previous Control Node is gone, you must regenerate the static credentials required to pull from GCS and run Terraform, and you **must** supply your Ansible Vault password to decrypt your repository.

1. **Recreate the Ansible Vault Password File:** Ansible looks for your master password at a specific local path (`~/.ansible_vault_pass`). Retrieve your password from your external password manager and inject it:
```bash
   echo "YOUR_ACTUAL_OLD_ANSIBLE_VAULT_PASSWORD" > ~/.ansible_vault_pass
   chmod 600 ~/.ansible_vault_pass
   ```
2. **Recover GCP Key:** Log into the Google Cloud Console, navigate to IAM & Admin -> Service Accounts, and generate a new JSON key for your backup service account.

3. **Export the variable:**
```bash
   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/new/gcp-credentials.json"
   ```

### Phase 3: Execute the Zero-Trust Restore Playbook
The restore process is governed by a **Zero-Trust Strategy**. To protect the Target Node from handling decryption keys directly, all decryption occurs locally on your new Control Node before data is securely pushed to the server over SSH.

1. **Run the Restore Playbook:**
```bash
   cd ansible
   ansible-playbook -i inventory/hosts.ini restore.yml
   ```
   **What Happens Automatically:**
   * Ansible authenticates with GCS and pulls the encrypted `.tar.gz.gpg` files to a secure local staging directory.

   * The archives are locally decrypted using your Vault-stored GPG passphrase.

   * Unencrypted archives are pushed to the Target Node over SSH.

   * Docker ephemeral containers (`alpine`) mount the volumes and extract the raw data directly into the named volumes.

   * The Control Node aggressively shreds and deletes all local decrypted staging files.

### Phase 4: Tier 3.5 Database Rehydration
Once the raw volumes are in place, boot the infrastructure:
```bash
ansible-playbook -i inventory/hosts.ini deploy.yml
```
During execution, the `deploy.yml` playbook will pause at the **Tier 3.5** block. It will explicitly wait for the newly booted Postgres container to accept connections, pipe the logical SQL dump back into the database, and only then proceed to boot the applications (Jenkins, Portainer, etc.) that rely on that data.

### Phase 5: Post-Restore Actions
1. **Unseal Vault:** Because Vault was restored from a backup, it will be sealed. Trigger the Jenkins pipeline (`Unseal-Vault.Jenkinsfile`), or manually unseal it using your keys.

2. **Verify Integrity:** Check Grafana dashboards and ensure all Cloudflare proxies are successfully routing traffic to the applications.