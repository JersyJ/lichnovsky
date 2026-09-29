resource "cloudflare_zero_trust_tunnel_cloudflared" "pi" {
  account_id = var.account_id
  name       = "lichnovsky-pi"
  config_src = "cloudflare"
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "pi" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.pi.id
}

locals {
  # Public hostnames. Deliberately NOT a wildcard: tv. (Jellyfin) and dns. (AdGuard) stay private.
  public_hosts = [
    var.domain, # website
    "www.${var.domain}",
    "vault.${var.domain}",
    "photos.${var.domain}",
    "papra.${var.domain}",
    "status.${var.domain}",
    "argocd.${var.domain}",
    "grafana.${var.domain}",
  ]
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "pi" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.pi.id

  config = {
    ingress = concat(
      [for h in local.public_hosts : { hostname = h, service = var.origin_service }],
      [{ service = "http_status:404" }], # required catch-all, must be last
    )
  }
}

resource "cloudflare_dns_record" "public" {
  for_each = toset(local.public_hosts)

  zone_id = var.zone_id
  name    = each.value
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.pi.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1 # "automatic"; required value for proxied records
  comment = "Cloudflare Tunnel lichnovsky-pi (managed by OpenTofu)"
}
