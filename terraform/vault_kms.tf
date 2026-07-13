# ==========================================
# HashiCorp Vault - GCP KMS Auto-Unseal
# ==========================================

# 1. Enable the KMS API
resource "google_project_service" "kms_api" {
  project            = "homelab-iac-rajiv"
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

# 2. Create the Vault Service Account
resource "google_service_account" "vault_kms_sa" {
  account_id   = "vault-kms-unseal"
  display_name = "Service Account for Vault Auto-Unseal"
  project      = "homelab-iac-rajiv"
}

# 3. Create the KeyRing
# Note: KeyRings cannot be deleted in GCP, only disabled.
resource "google_kms_key_ring" "vault_keyring" {
  name     = "homelab-vault-keyring"
  location = "global"
  project  = "homelab-iac-rajiv"

  depends_on = [google_project_service.kms_api]
}

# 4. Create the CryptoKey
resource "google_kms_crypto_key" "vault_cryptokey" {
  name     = "vault-master-key"
  key_ring = google_kms_key_ring.vault_keyring.id
  purpose  = "ENCRYPT_DECRYPT"

  # Optional: Automatically rotate the encryption key every 90 days
  rotation_period = "7776000s"

  lifecycle {
    prevent_destroy = true
  }
}

# 5. Grant the Vault Service Account permissions to use the key
resource "google_kms_crypto_key_iam_binding" "vault_kms_binding" {
  crypto_key_id = google_kms_crypto_key.vault_cryptokey.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_service_account.vault_kms_sa.email}"
  ]
}

resource "google_kms_crypto_key_iam_binding" "vault_kms_viewer_binding" {
  crypto_key_id = google_kms_crypto_key.vault_cryptokey.id
  role          = "roles/cloudkms.viewer"

  members = [
    "serviceAccount:${google_service_account.vault_kms_sa.email}"
  ]
}

# Output the Service Account email so we know which one to generate a JSON key for
output "vault_kms_service_account" {
  value       = google_service_account.vault_kms_sa.email
  description = "Generate a JSON key for this SA and save it to your Ansible vault."
}
