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
  backend "gcs" {
    bucket  = "rajiv-homelab-tf-state" # Manually create this ONE bucket in GCP Console first
    prefix  = "terraform/state"
  }
}

provider "google" {
  credentials = file(var.gcp_credentials_file)
  project     = var.gcp_project_id
  region      = var.gcp_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}