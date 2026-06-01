variable "gcp_region" {
  description = "Default region for resources"
  type        = string
  default     = "us-east1"
}

variable "backup_bucket_name" {
  description = "Globally unique name for the backup bucket"
  type        = string
  default     = "homelab-backups-rajiv-wallace"
}