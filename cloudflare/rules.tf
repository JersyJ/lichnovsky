# Free plan: 1 rate limiting rule, path-only matching, per-IP counting over 10 s.
resource "cloudflare_ruleset" "rate_limit" {
  zone_id = var.zone_id
  name    = "Rate limiting"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [{
    description = "Brute-force protection for Vaultwarden and Immich logins"
    expression  = "(http.request.uri.path contains \"/identity/connect/token\") or (http.request.uri.path contains \"/api/auth/login\")"
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
    description = "Website: eligible for cache, respect origin headers"
    expression  = "(http.host eq \"${var.domain}\")"
    action      = "set_cache_settings"
    action_parameters = {
      cache       = true
      edge_ttl    = { mode = "respect_origin" }
      browser_ttl = { mode = "respect_origin" }
    }
  }]
}
