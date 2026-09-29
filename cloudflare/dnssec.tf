# DNSSEC: Cloudflare signs the zone. To complete the chain of trust, the DS record below must be
# entered ONCE at the registrar (Porkbun -> lichnovsky.eu -> DNSSEC). Until then, nothing is
# validated and nothing breaks. See `tofu output dnssec_ds` after apply.
resource "cloudflare_zone_dnssec" "this" {
  zone_id = var.zone_id
  status  = "active"
}
