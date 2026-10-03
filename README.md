# lichnovsky.eu

This repository contains the [lichnovsky.eu](https://lichnovsky.eu) homelab. The homelab is k3s on
a Raspberry Pi 5. Argo CD deploys it from this repository.

- Public apps go through Cloudflare Tunnel.
- Private apps are available only at home and through Tailscale.
- Each night, encrypted backups go to the SD card in the Pi.
- Alerts go to Discord.

| App | URL | Public | Cloudflare Access |
|---|---|---|---|
| Website (in progress, [web/](web)) | https://lichnovsky.eu (`www.` redirects) | Yes | No |
| Vaultwarden | https://vault.lichnovsky.eu | Yes | Only `/admin` (Access on the full host stops the Bitwarden apps) |
| Papra | https://papra.lichnovsky.eu | Yes | Yes |
| Uptime Kuma | https://status.lichnovsky.eu | Yes | Yes. The status page `/status/home` is public |
| Argo CD | https://argocd.lichnovsky.eu | Yes | Yes |
| Grafana | https://grafana.lichnovsky.eu | Yes | Yes |
| Gokapi (share videos and files, [guide](docs/share.md)) | https://share.lichnovsky.eu | Yes | No (Gokapi accounts for upload, public links for download) |
| Jellyfin | https://tv.lichnovsky.eu | No | – |
| AdGuard Home | https://dns.lichnovsky.eu | No | – |
| Seerr (requests for Jellyfin) | https://watchlist.lichnovsky.eu | No | – |
| Sonarr (series), Radarr (movies) | https://sonarr.lichnovsky.eu, https://radarr.lichnovsky.eu | No | – |
| Prowlarr (indexers), Bazarr (subtitles) | https://prowlarr.lichnovsky.eu, https://bazarr.lichnovsky.eu | No | – |
| qBittorrent | https://qbit.lichnovsky.eu | No | – |
| Immich (not deployed) | https://photos.lichnovsky.eu | Yes | No (the apps and share links need direct access) |

All apps are also available at home and through Tailscale. For the details, refer to
[architecture.md](docs/architecture.md#three-ways-in-one-set-of-urls).

## Documents

- [architecture.md](docs/architecture.md): the components, the traffic flow, and the reason for
  each choice
- [setup.md](docs/setup.md): the installation from zero, in sequence
- [operations.md](docs/operations.md): changes, updates, alerts, backups, restores and
  troubleshooting
- [movies-and-series.md](docs/movies-and-series.md): for family members. How to watch in Jellyfin
  and how to make requests in Seerr
- [share.md](docs/share.md): for persons with a Gokapi account. How to share a video with a link

## Layout

```
bootstrap/    apply one time by hand: the Argo CD values and the root app
argocd/       one Application for each component. Argo CD deploys each file here (later/ = not yet)
platform/     platform layer: namespaces, Traefik, TLS, tunnel, monitoring, backups
apps/         application layer
web/          source of the website (Astro). CI builds the image that apps/web deploys
cloudflare/   OpenTofu for the Cloudflare infrastructure
host/         files for the Pi, numbered in run sequence
scripts/      seal.sh (make secrets), validate.py (checks before a push)
.github/      Renovate, gitleaks, the CI workflow of the website
```

## Rules

- **Do not put secrets in plain text.** Make each secret with `scripts/seal.sh <name>`. A Git hook
  stops `kind: Secret`.
- **Versions are pinned.** Renovate makes pull requests for updates.
