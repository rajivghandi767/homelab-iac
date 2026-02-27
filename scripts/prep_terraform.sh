#!/bin/bash
set -e

cd "$(dirname "$0")/../ansible"

echo "🔐 Enter your Ansible Vault Password to unlock GCP keys:"
ansible-playbook extract_gcp_key.yml --ask-vault-pass