# cloudflare/: Cloudflare as code (OpenTofu)

Manages everything on the Cloudflare side of lichnovsky.eu:

| File | What |
|---|---|
| `tunnel.tf` | Tunnel `lichnovsky-pi`, its routing (public hostnames → Traefik), proxied DNS records |
| `access.tf` | Cloudflare Access (e-mail one-time PIN) for Argo CD, Grafana, Papra, Uptime Kuma, Vaultwarden `/admin` |
| `rules.tf` | Login rate limit (Free plan: 1 rule), cache rule for the website |
| `zone.tf` | TLS settings: Full (strict), Always Use HTTPS, TLS ≥ 1.2 |
| `outputs.tf` | `tunnel_token`, which `scripts/seal.sh cloudflared-token` seals for cloudflared |

State: Cloudflare R2 bucket `lichnovsky-tofu-state`, **encrypted by OpenTofu before upload**
(AES-GCM, key derived from your passphrase). Locking uses R2 conditional writes (`use_lockfile`).

## One-time bootstrap (manual, in the dashboard)

1. **R2**: dashboard → R2 Object Storage → enable. This can ask for a payment method; the free tier
   (10 GB-month) covers this state file many thousand times over. Then *Create bucket*
   `lichnovsky-tofu-state` (location: automatic).
2. **R2 API token** (R2 → Manage API tokens → *Create API token*): permission *Object Read & Write*,
   limited to bucket `lichnovsky-tofu-state`. Save the **Access Key ID** and **Secret Access Key**.
3. **OpenTofu API token** (My Profile → API Tokens → *Create Token* → *Custom token*):

   | Scope | Permission |
   |---|---|
   | Account | Cloudflare Tunnel: **Edit** |
   | Account | Access: Apps and Policies: **Edit** |
   | Account | Account Rulesets: **Edit** |
   | Account | Account Filter Lists: **Edit** |
   | Zone | Zone: **Read** |
   | Zone | DNS: **Edit** |
   | Zone | Zone Settings: **Edit** |
   | Zone | Zone WAF: **Edit** |
   | Zone | Cache Rules: **Edit** |

   Account resources: your account. Zone resources: *Specific zone → lichnovsky.eu*.
4. **Zero Trust** must be initialised once: sidebar → Zero Trust → pick a team name and the
   **Free** plan. The One-time PIN login method is available by default.
5. Your **account ID** and **zone ID** are in `terraform.tfvars` (and the account ID in the R2
   endpoint in `provider.tf`).

## Usage

OpenTofu is installed with [tenv](https://github.com/tofuutils/tenv), which picks up the pinned
version from `.opentofu-version` in the repo root (`tenv tofu install`).

```bash
export CLOUDFLARE_API_TOKEN=...          # OpenTofu token (3.)
export AWS_ACCESS_KEY_ID=...             # R2 token (2.)
export AWS_SECRET_ACCESS_KEY=...
export TF_VAR_state_passphrase=...       # >= 16 chars, from your password manager

cd cloudflare
tofu init
tofu plan
tofu apply
```

Tip: keep those four in your password manager and load them with a small untracked script
(e.g. `source ~/.config/lichnovsky/cloudflare.env`). **Lose the passphrase and the state can't be
decrypted.** You'd have to re-import the resources.

The cert-manager DNS token stays a manual, separate token (Zone:DNS:Edit on lichnovsky.eu only).
Creating it from code would need a token that can mint tokens, which is effectively full control
of the account.
