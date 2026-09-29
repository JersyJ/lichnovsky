# cloudflare/

Everything on the Cloudflare side as OpenTofu: tunnel and its public hostnames, DNS, Access, rate
limit and cache rule, TLS settings, DNSSEC and the heartbeat Worker.

State: Cloudflare R2 bucket `lichnovsky-tofu-state`, **encrypted by OpenTofu**
(AES-GCM, key derived from your passphrase) due to tunnel secret.

## Secrets

| Variable | What |
|---|---|
| `CLOUDFLARE_API_TOKEN` | OpenTofu token (below) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | R2 token; R2 speaks the S3 API, nothing talks to AWS |
| `TF_VAR_state_passphrase` | encrypts the state; **lose it and the state is unreadable** (resources would have to be re-imported) |
| `TF_VAR_discord_webhook_url` | where the heartbeat Worker posts |

## One-time setup in the dashboard

1. **R2** → enable (may ask for a payment method; the free tier covers this many times over) →
   *Create bucket* `lichnovsky-tofu-state`.
2. **R2 → Manage API tokens** → *Object Read & Write*, only bucket `lichnovsky-tofu-state`.
3. **My Profile → API Tokens → Custom token**, account resources: your account, zone resources:
   `lichnovsky.eu`:

   | Account | Zone |
   |---|---|
   | Cloudflare Tunnel: Edit | Zone: Read |
   | Access: Apps and Policies: Edit | DNS: Edit |
   | Account Rulesets: Edit | Zone Settings: Edit |
   | Account Filter Lists: Edit | Zone WAF: Edit |
   | Workers Scripts: Edit | Cache Rules: Edit |
   | Workers KV Storage: Edit | |

4. **Zero Trust** → pick a team name and the Free plan (needed once before Access works).

The account and zone IDs are in `terraform.tfvars`. The cert-manager DNS token is separate and
made by hand ([docs/setup.md, step 1](../docs/setup.md#1-accounts)).
