# Country Trivia

This directory is a placeholder for the Country Trivia Web application.

## Getting Started

The Country Trivia game is maintained in its own repository with full source code, documentation, and deployment instructions.

### Clone and Deploy

```bash
# Navigate to this directory
cd services/applications/country-trivia-web

# Clone the latest version
git clone https://github.com/rajivghandi767/country-trivia-web.git .

# Follow the setup instructions in the cloned repository
# Typically:
# 1. Configure environment variables
# 2. Build Docker images
# 3. Start services with docker-compose
```

## Repository

**GitHub:** https://github.com/rajivghandi767/country-trivia-web

## Quick Links

- Live Game: https://trivia.rajivwallace.com
- GitHub Repository: [rajivghandi767/country-trivia-web](https://github.com/rajivghandi767/country-trivia-web)
- Tech Stack: Django REST Framework, React, TypeScript, PostgreSQL

## Integration with Homelab

Once deployed, this application will:

- Connect to the `trivia` and `database` Docker networks
- Be monitored by Prometheus
- Be accessible at https://trivia.rajivwallace.com

## Notes

- This is a separate Git repository - do not commit it as part of homelab-iac
- See the main repository for detailed setup and deployment instructions
