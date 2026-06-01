terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  backend "gcs" {
    bucket  = "rajiv-homelab-tf-state"
    prefix  = "terraform/state"
  }
}

provider "google" {
  project = "homelab-iac-rajiv"
  region  = var.gcp_region
}

provider "cloudflare" {
  # Dynamically injected from the GCP Secret Manager data block
  api_token = data.google_secret_manager_secret_version.cf_token.secret_data
}