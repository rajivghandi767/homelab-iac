#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Rajiv's Homelab - Bootstrap Protocol     ${NC}"
echo -e "${GREEN}============================================${NC}"

# --- PRE-FLIGHT CHECKS ---
if [ ! -f "secrets/.env" ]; then
    echo -e "${RED}[ERROR] secrets/.env is missing!${NC}"
    echo "1. cp secrets/.env.example secrets/.env"
    echo "2. Populate it with GCS keys and passwords."
    exit 1
fi

if [ ! -f "ansible/inventory/hosts.ini" ]; then
    echo -e "${RED}[ERROR] Inventory file missing!${NC}"
    exit 1
fi

# --- STEP 1: INSTALL ANSIBLE ---
if ! command -v ansible &> /dev/null; then
    echo -e "${BLUE}[1/4] Installing Ansible...${NC}"
    sudo apt-get update && sudo apt-get install -y ansible python3-pip
    # Install GCP dependencies for Ansible
    pip3 install requests google-auth
else
    echo -e "${GREEN}[1/4] Ansible already installed.${NC}"
fi

# Install Galaxy Collections (Needed for GCP/Docker modules)
echo -e "${BLUE}      Installing Ansible Collections...${NC}"
ansible-galaxy collection install google.cloud community.docker community.general > /dev/null

# --- STEP 2: FOUNDATION (System, Docker, Cron, Networks) ---
echo -e "\n${BLUE}[2/4] Running Foundation Playbook...${NC}"
# This sets up Docker, Folders, Networks, and the Backup Cron Job
ansible-playbook -i ansible/inventory/hosts.ini ansible/foundation.yml

# --- STEP 3: RESTORE DECISION ---
echo -e "\n${BLUE}[3/4] Disaster Recovery${NC}"
read -p "      Do you want to restore Volumes from GCP Backups? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}      Starting Restoration (Decryption & Volume Injection)...${NC}"
    # Note: --ask-vault-pass is needed because secrets.yml is encrypted
    ansible-playbook -i ansible/inventory/hosts.ini ansible/restore.yml --ask-vault-pass
else
    echo -e "      Skipping Restore. Starting with empty volumes."
fi

# --- STEP 4: LAUNCH SERVICES ---
echo -e "\n${BLUE}[4/4] Launching Docker Containers...${NC}"

# Define launch order
FILES=(
    "foundation/docker-compose.foundation.yml"
    "services/core/docker-compose.yml"
    "services/database/docker-compose.yml"
    "services/monitoring/docker-compose.yml"
    "services/media/docker-compose.yml"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "      Booting $file..."
        docker compose -f "$file" up -d
    else
        echo -e "${RED}      Warning: $file not found!${NC}"
    fi
done

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}   DEPLOYMENT COMPLETE                      ${NC}"
echo -e "${GREEN}============================================${NC}"
echo -e "   • Jenkins:    http://$(hostname -I | awk '{print $1}'):8080"
echo -e "   • Portainer:  http://$(hostname -I | awk '{print $1}'):9000"
echo -e "   • NPM:        http://$(hostname -I | awk '{print $1}'):81"