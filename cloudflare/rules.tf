# Free plan: 1 rate limiting rule, path-only matching, per-IP counting over 10 s.
resource "cloudflare_ruleset" "rate_limit" {
  zone_id = var.zone_id
  name    = "Rate limiting"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    description = "Brute-force protection for the Vaultwarden, Immich and Gokapi logins"
    expression  = "(http.request.uri.path contains \"/identity/connect/token\") or (http.request.uri.path contains \"/api/auth/login\") or (http.request.uri.path eq \"/login\")"
    action      = "block"
    ratelimit = {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10
      requests_per_period = 10
      mitigation_timeout  = 10
    }
  }]
}

# Cache the website at the edge, honouring the Cache-Control headers the site sends.
resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "Cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [{
    description = "Website: eligible for cache, respect origin headers (never the health check)"
    expression  = "(http.host eq \"${var.domain}\" and http.request.uri.path ne \"/healthz\")"
    action      = "set_cache_settings"
    action_parameters = {
      cache       = true
      edge_ttl    = { mode = "respect_origin" }
      browser_ttl = { mode = "respect_origin" }
    }
  }]
}

# Drop the X-Forwarded-For that a visitor sends. Cloudflare adds it again with only the visitor's
# IP, so the first entry is the real client (Vaultwarden reads it; Traefik logs it).
resource "cloudflare_ruleset" "request_headers" {
  zone_id = var.zone_id
  name    = "Request header changes"
  kind    = "zone"
  phase   = "http_request_late_transform"

  rules = [{
    description = "Remove the visitor's own X-Forwarded-For"
    expression  = "true"
    action      = "rewrite"
    action_parameters = {
      headers = {
        "X-Forwarded-For" = { operation = "remove" }
      }
    }
  }]
}
