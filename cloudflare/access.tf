# Cloudflare Access (Zero Trust) in front of the admin UIs. Login = one-time PIN to your e-mail.
resource "cloudflare_zero_trust_access_policy" "owner" {
  account_id       = var.account_id
  name             = "Owner"
  decision         = "allow"
  include          = [for e in var.access_emails : { email = { email = e } }]
  session_duration = "24h"
}

locals {
  protected_apps = {
    "Argo CD"     = "argocd.${var.domain}"
    "Grafana"     = "grafana.${var.domain}"
    "Papra"       = "papra.${var.domain}"
    "Uptime Kuma" = "status.${var.domain}"
    # Only the admin page: protecting all of vault. would break the Bitwarden apps.
    "Vaultwarden admin" = "vault.${var.domain}/admin"
    # photos. (Immich) is intentionally NOT behind Access: its apps and share links need direct access.
  }
}

resource "cloudflare_zero_trust_access_application" "admin" {
  for_each = local.protected_apps

  account_id       = var.account_id
  name             = each.key
  type             = "self_hosted"
  domain           = each.value
  session_duration = "24h"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.owner.id
    precedence = 1
  }]
}
