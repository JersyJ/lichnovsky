output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.pi.id
}

# Read by `scripts/seal.sh cloudflared-token`; never printed by default.
output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.pi.token
  sensitive = true
}

# For Porkbun's DNSSEC form (.eu uses keyData). Max Sig Life: leave empty.
output "dnssec_ds" {
  value = {
    key_tag     = cloudflare_zone_dnssec.this.key_tag
    algorithm   = cloudflare_zone_dnssec.this.algorithm
    digest_type = cloudflare_zone_dnssec.this.digest_type
    digest      = cloudflare_zone_dnssec.this.digest
    ds_record   = cloudflare_zone_dnssec.this.ds
  }
}

output "dnssec_keydata" {
  value = {
    flags      = cloudflare_zone_dnssec.this.flags # 257 = key-signing key (KSK)
    protocol   = 3                                 # always 3 for DNSSEC
    algorithm  = cloudflare_zone_dnssec.this.algorithm
    public_key = cloudflare_zone_dnssec.this.public_key
  }
}
