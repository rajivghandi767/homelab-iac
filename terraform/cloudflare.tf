data "cloudflare_zone" "main" {
  name = "rajivwallace.com"
}

# 1. DDNS IP Tracker (Updated by UniFi DDNS)
resource "cloudflare_record" "ddns_ip" {
  zone_id = data.cloudflare_zone.main.id
  name    = "ddns"
  content = "192.0.2.1" # Dummy IP; managed externally
  type    = "A"
  proxied = false

  lifecycle {
    ignore_changes = [content]
  }
}

# 2. The Anchor: Root Record
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = cloudflare_record.ddns_ip.hostname
  type    = "CNAME"
  proxied = true
}

# 3. Public Services (The web infrastructure you control)
resource "cloudflare_record" "public_services" {
  for_each = toset([
    "www",
    "portfolio-api", 
    "trivia", 
    "trivia-api",
    "prop-ferry",
    "prop-ferry-api",  
    "svt", 
    "svt-api",
    "jenkins", 
    "jellyfin"
  ])
  
  zone_id = data.cloudflare_zone.main.id
  name    = each.key
  content = cloudflare_record.ddns_ip.hostname
  type    = "CNAME"
  proxied = true
}

# 4. Unproxied Services (VPN)
resource "cloudflare_record" "unproxied_public_services" {
  zone_id = data.cloudflare_zone.main.id
  name    = "vpn"
  content = cloudflare_record.ddns_ip.hostname
  type    = "CNAME"
  proxied = false
}

# 3. Local Services (Your internal LAN infrastructure)
resource "cloudflare_record" "local_services" {
  for_each = toset([
    "vault", 
    "portainer", 
    "nginx", 
    "pgadmin", 
    "unifi", 
    "redis", 
    "alertmanager", 
    "cadvisor", 
    "grafana", 
    "pihole", 
    "prometheus",
  ])

  zone_id = data.cloudflare_zone.main.id
  name    = each.key
  content = data.google_secret_manager_secret_version.local_ip.secret_data
  type    = "A"
  proxied = false
}