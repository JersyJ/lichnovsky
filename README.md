# lichnovsky.eu

The [lichnovsky.eu](https://lichnovsky.eu) homelab: k3s on a Raspberry Pi 5, deployed by Argo CD from this repository.
Public apps go through Cloudflare Tunnel, private ones are reachable at home and over Tailscale.
Nightly encrypted backups go to the Pi's SD card; alerts go to Discord.

| App | URL | Public | Cloudflare Access |
|---|---|---|---|
| Website (in progress: placeholder with a live status widget) | https://lichnovsky.eu (`www.` redirects) | yes | no |
| Vaultwarden | https://vault.lichnovsky.eu | yes | only `/admin` (the whole host would break the Bitwarden apps) |
| Papra | https://papra.lichnovsky.eu | yes | yes |
| Uptime Kuma | https://status.lichnovsky.eu | yes | yes; the status page `/status/home` is public |
| Argo CD | https://argocd.lichnovsky.eu | yes | yes |
| Grafana | https://grafana.lichnovsky.eu | yes | yes |
| Jellyfin | https://tv.lichnovsky.eu | no | – |
| AdGuard Home | https://dns.lichnovsky.eu | no | – |
| Immich (not deployed yet) | https://photos.lichnovsky.eu | yes | no (the apps and share links need direct access) |

Every app is also reachable at home and over Tailscale;
[architecture.md](docs/architecture.md#three-ways-in-one-set-of-urls) explains how.

## Docs

- [architecture.md](docs/architecture.md): what runs, how traffic flows, why each choice
- [setup.md](docs/setup.md): building it from zero, in order
- [operations.md](docs/operations.md): changes, updates, alerts, backups, restores, troubleshooting

## Layout

```
bootstrap/    applied by hand once: Argo CD values + the root app
argocd/       one Application per component; a file here gets deployed (later/ = not yet)
platform/     Platform layer - namespaces, Traefik, TLS, tunnel, monitoring, backups
apps/         Application layer
cloudflare/   OpenTofu for the infrastructure on Cloudflare side
host/         files for the Pi itself, numbered in run order
scripts/      seal.sh (create secrets), validate.py (check before push)
```

## Rules

- **No plaintext secrets.** Create each secret with `scripts/seal.sh <name>`; a git hook blocks `kind: Secret`.
- **Versions are pinned.** Renovate proposes updates as PRs.
