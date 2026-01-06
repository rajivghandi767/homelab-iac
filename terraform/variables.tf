variable "gcp_project_id" {
  description = "The ID of the Google Cloud Project"
  type        = string
}

variable "gcp_region" {
  description = "Default region for resources"
  type        = string
  default     = "us-east1"
}

variable "gcp_credentials_file" {
  description = "Path to the JSON key file"
  type        = string
  default     = "../secrets/gcp-credentials.json"
}

variable "backup_bucket_name" {
  description = "Globally unique name for the backup bucket"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API Token with DNS:Edit permissions"
  type        = string
  sensitive   = true
}

variable "homelab_public_ip" {
  description = "Your Home IP address"
  type        = string
}

variable "local_network_ip" {
  description = "The internal IP of your Pi"
  type        = string
  default     = "10.100.10.5" # Replace with your Pi's actual LAN IP
}