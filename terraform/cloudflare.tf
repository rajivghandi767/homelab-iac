data "cloudflare_zone" "main" {
  name = "rajivwallace.com"
}

# --- 1. Public Edge (Proxied via Cloudflare) ---
# These are safe to expose because NPM handles the SSL/Auth
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  value   = var.homelab_public_ip
  type    = "A"
  proxied = true 
}

resource "cloudflare_record" "public_cnames" {
  for_each = toset(["www", "trivia-api", "trivia", "portfolio-api", "portfolio", "jenkins", "jellyfin", "vpn"])
  
  zone_id = data.cloudflare_zone.main.id
  name    = each.key
  value   = "rajivwallace.com"
  type    = "CNAME"
  proxied = true
}

# --- 2. Private/Local Access (Direct LAN IP) ---
# These bypass Cloudflare Proxy. Useful for admin panels you don't want exposed 
# to the public internet, or for split-horizon DNS inside your home.
resource "cloudflare_record" "local_services" {
  for_each = toset(["jenkins", "vault", "portainer", "nginx", "pgadmin", "unifi"])

  zone_id = data.cloudflare_zone.main.id
  name    = each.key
  value   = var.local_network_ip # e.g., 192.168.1.100
  type    = "A"
  proxied = false 
  # Note: You must be on your home Wi-Fi/VPN to access these!
}