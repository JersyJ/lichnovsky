# cloudflare/

OpenTofu controls all of the Cloudflare configuration:

- the tunnel and its public hostnames
- DNS
- Access
- the rate limit and the cache rule
- the TLS settings and DNSSEC
- the heartbeat Worker

The OpenTofu state is in the Cloudflare R2 bucket `lichnovsky-tofu-state`. OpenTofu encrypts the
state (AES-GCM, with a key from your passphrase), because the state contains the tunnel secret.

## Secrets

| Variable | Function |
|---|---|
| `CLOUDFLARE_API_TOKEN` | The OpenTofu token (refer to the steps below) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | The R2 token. R2 uses the S3 API. No data goes to AWS. |
| `TF_VAR_state_passphrase` | Encrypts the state. **If you lose it, you cannot read the state.** Then you must import all resources again. |
| `TF_VAR_discord_webhook_url` | The heartbeat Worker sends its messages to this webhook. |

## Do these steps one time in the dashboard

1. **R2:** Enable R2. Cloudflare can ask for a payment method. The free tier is sufficient. Make
   the bucket `lichnovsky-tofu-state` (*Create bucket*).
2. **R2 → Manage API tokens:** Make a token with *Object Read & Write*, only for the bucket
   `lichnovsky-tofu-state`.
3. **My Profile → API Tokens → Custom token:** Set the account resources to your account. Set the
   zone resources to `lichnovsky.eu`. Give these permissions:

   | Account | Zone |
   |---|---|
   | Cloudflare Tunnel: Edit | Zone: Read |
   | Access: Apps and Policies: Edit | DNS: Edit |
   | Account Rulesets: Edit | Zone Settings: Edit |
   | Account Filter Lists: Edit | Zone WAF: Edit |
   | Workers Scripts: Edit | Cache Rules: Edit |
   | Workers KV Storage: Edit | |

4. **Zero Trust:** Select a team name and the Free plan. Access does not work before you do this
   step.

The account ID and the zone ID are in `terraform.tfvars`. The DNS token for cert-manager is a
different token. You make it by hand, refer to [docs/setup.md, step 1](../docs/setup.md#1-accounts).
