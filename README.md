# lichnovsky

GitOps repository (github.com/JersyJ/lichnovsky) for **lichnovsky.eu**, the website and homelab: k3s on a Raspberry Pi 5,
driven by Argo CD. Public apps go through Cloudflare Tunnel, private ones through the LAN and
Tailscale. Nightly encrypted backups go to the Pi's SD card; alerts go to Discord.

| App | URL | Reachable from |
|---|---|---|
| Website | https://lichnovsky.eu (`www.` redirects) | Internet, LAN, Tailscale |
| Vaultwarden | https://vault.lichnovsky.eu | Internet, LAN, Tailscale |
| Immich | https://photos.lichnovsky.eu | Internet, LAN, Tailscale |
| Papra | https://papra.lichnovsky.eu | Internet (Access), LAN, Tailscale |
| Uptime Kuma | https://status.lichnovsky.eu | Internet (Access), LAN, Tailscale |
| Argo CD | https://argocd.lichnovsky.eu | Internet (Access), LAN, Tailscale |
| Grafana | https://grafana.lichnovsky.eu | Internet (Access), LAN, Tailscale |
| Jellyfin | https://tv.lichnovsky.eu | LAN, Tailscale |
| AdGuard Home | https://dns.lichnovsky.eu | LAN, Tailscale |

The website itself is built in a separate repository. Until it's ready, a placeholder page runs
here (`apps/web/website`); see the image contract in the guide, §11.

## Start here

1. Read **[docs/guide.md](docs/guide.md)**: architecture, RAM budget, and the step-by-step build.
2. Replace the placeholders: `grep -rn CHANGEME .`
3. Tooling: install kubectl, helm, kubeseal, kubeconform, uv, prek and OpenTofu (via tenv); then `prek install`
   for the git hooks.
4. The cluster comes up in **five stages**: only `argocd/*.yaml` is deployed, and the rest waits in
   `argocd/later/` ([how to enable a stage](argocd/later/README.md)).

## Layout

```
bootstrap/   Argo CD Helm values + the root "app of apps"
argocd/      enabled Applications (sync-wave ordered); later/ holds stages 2-5
apps/        plain manifests per app (plus SealedSecrets once you create them)
host/        files that go on the Pi itself
scripts/     secrets workflow + offline validation
docs/        guide + review of the original draft
```

## Rules of the repo

- **Never commit a plaintext Secret.** Create each one with `scripts/seal.sh <name>`: it writes only the
  SealedSecret, never plaintext. A hook blocks any `kind: Secret`.
- **Pin every version.** Renovate proposes updates as PRs.
- **Git is the source of truth.** Anything changed with `kubectl edit` is reverted by self-heal.
