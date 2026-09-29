variable "state_passphrase" {
  description = "Passphrase for OpenTofu state/plan encryption (>= 16 characters). Set TF_VAR_state_passphrase."
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare account ID (dashboard -> lichnovsky.eu -> Overview, right column)."
  type        = string
}

variable "zone_id" {
  description = "Zone ID of lichnovsky.eu (same place as the account ID)."
  type        = string
}

variable "domain" {
  type    = string
  default = "lichnovsky.eu"
}

variable "access_emails" {
  description = "E-mail addresses allowed through Cloudflare Access (one-time PIN login)."
  type        = list(string)
}

variable "origin_service" {
  description = "Where cloudflared sends every public request: Traefik inside the cluster."
  type        = string
  default     = "http://traefik.kube-system.svc.cluster.local:80"
}
