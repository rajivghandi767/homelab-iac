data "cloudflare_zone" "main" {
  name = "rajivwallace.com"
}

# 1. The Anchor: Root A Record
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = "@"
  content = var.homelab_public_ip
  type    = "A"
  proxied = true
}

# 2. Public Services (The web infrastructure you control)
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
    "jellyfin", 
    "vpn"
  ])
  
  zone_id = data.cloudflare_zone.main.id
  name    = each.key
  content = var.homelab_public_ip
  type    = "A"
  proxied = true
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
  content = var.local_network_ip
  type    = "A"
  proxied = false
}