resource "cloudflare_zone_dnssec" "this" {
  zone_id = var.zone_id
  status  = "active"
}
