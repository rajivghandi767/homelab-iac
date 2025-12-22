# Portfolio Website

This directory is a placeholder for the Portfolio Website application.

## Getting Started

The Portfolio Website is maintained in its own repository with full source code, documentation, and deployment instructions.

### Clone and Deploy

```bash
# Navigate to this directory
cd services/applications/portfolio-website

# Clone the latest version
git clone https://github.com/rajivghandi767/portfolio-website.git .

# Follow the setup instructions in the cloned repository
# Typically:
# 1. Configure environment variables
# 2. Build Docker images
# 3. Start services with docker-compose
```

## Repository

**GitHub:** https://github.com/rajivghandi767/portfolio-website

## Quick Links

- Live Site: https://rajivwallace.com
- GitHub Repository: [rajivghandi767/portfolio-website](https://github.com/rajivghandi767/portfolio-website)
- Tech Stack: Django REST Framework, React, TypeScript, PostgreSQL

## Integration with Homelab

Once deployed, this application will:

- Connect to the `portfolio` and `database` Docker networks
- Be monitored by Prometheus
- Be accessible at https://rajivwallace.com

## Notes

- This is a separate Git repository - do not commit it as part of homelab-iac
- See the main repository for detailed setup and deployment instructions
