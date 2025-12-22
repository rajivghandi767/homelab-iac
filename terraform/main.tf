resource "google_storage_bucket" "homelab_backups" {
  name          = var.backup_bucket_name
  location      = "US"
  force_destroy = false # Prevent accidental deletion if bucket has data

  uniform_bucket_level_access = true

  # 1. Versioning: Keep history if a backup is corrupted/overwritten
  versioning {
    enabled = true
  }

  # 2. Lifecycle: Automatically delete old backups to save money
  lifecycle_rule {
    condition {
      age = 30 # Delete objects older than 30 days
    }
    action {
      type = "Delete"
    }
  }

  # 3. Security: Ensure encryption is enabled (Google manages keys by default)
  # But we explicitly block public access
  public_access_prevention = "enforced"
}

# Output the URL so we can use it in our scripts later
output "backup_bucket_url" {
  value = google_storage_bucket.homelab_backups.url
}