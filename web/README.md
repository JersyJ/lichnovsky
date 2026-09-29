# web/

The lichnovsky.eu website: an [Astro](https://docs.astro.build) static site, served by unprivileged
nginx on the Pi. The Kubernetes side is in [apps/web](../apps/web).

## Develop

```bash
cd web
npm install
npm run dev        # http://localhost:4321, reloads on save
npm run build      # static files in dist/, exactly what gets deployed
```
In `npm run dev`, the status widget shows live data: `/status-data/…` is proxied to the public
status page (`astro.config.mjs`).

| Path | What |
|---|---|
| `src/pages/` | one file per URL (`index.astro` → `/`, `404.astro` → the not-found page) |
| `src/layouts/Base.astro` | the HTML shell and global styles |
| `src/components/Status.astro` | the live status widget |
| `public/` | files copied as-is (favicon, images); create it when needed |
| `nginx.conf` | how the image serves the site: cache headers, `/healthz`, the `/status-data/` proxy |
| `Dockerfile` | builds the site, then copies it into the nginx image |

## Deploy

Push to `main`. When anything in `web/` changed, GitHub Actions (`.github/workflows/web.yml`):
1. builds the image for arm64 and amd64 and pushes it to `ghcr.io/jersyj/lichnovsky-web:sha-<commit>`,
2. commits that tag into `apps/web/kustomization.yaml` as `github-actions[bot]`,
3. Argo CD rolls it out within ~3 minutes (two pods, one at a time, no downtime).

The bot's commit means your local `main` is one commit behind: `git pull --rebase` before the next push.

**Rolling back:** set `newTag` in `apps/web/kustomization.yaml` to an earlier `sha-…` tag and push.

## Rules the image has to keep

- Listen on **8080** as non-root, with a read-only root filesystem (only `/tmp` is writable): the
  `web` namespace enforces the `restricted` Pod Security profile.
- `GET /healthz` returns 200: the probes and the external heartbeat use it.
- Send `Cache-Control` headers: Cloudflare caches the site by them, and would cache a page for 2 hours
  without one. `nginx.conf` does this: hashed assets in `/_astro/` forever, pages for 60 s.
