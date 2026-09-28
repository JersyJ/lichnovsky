output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.pi.id
}

# Read by scripts/secrets.sh init to fill the cloudflared SealedSecret; never printed by default.
output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.pi.token
  sensitive = true
}
