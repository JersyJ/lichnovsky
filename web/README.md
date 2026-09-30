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
In `npm run dev`, the station dots show live data: `/status-data/…` is proxied to the public
status page (`astro.config.mjs`).

| Path | What |
|---|---|
| `src/data/services.ts` | the stations on the map: name, URL, line (Apps / Admin), access, status monitor |
| `src/pages/` | one file per URL (`index.astro` → `/`, `404.astro` → the not-found page) |
| `src/layouts/Base.astro` | the HTML shell, fonts (Overpass, self-hosted) and the colour tokens (light, and dark following the system) |
| `src/components/` | `Map` (the network map on wide screens), `Strip` (the same map as a vertical line on phones), `Status` (live status line and station dots) |
| `public/` | files copied as-is (`favicon.svg`) |
| `nginx.conf` | how the image serves the site: cache headers, `/healthz`, the `/status-data/` proxy |
| `Dockerfile` | builds the site, then copies it into the slim unprivileged nginx image and checks the config |

**Adding a service:** one entry in the right line in `src/data/services.ts`; the map spaces the
stations itself. Set `access` (`public`, `sign-in` for Cloudflare Access, `private` for home and
Tailscale only). For a live status dot, set `monitor` to the monitor's name on the public status page
`home` in Uptime Kuma (and add the monitor to that page). `planned: true` draws a station that isn't
open yet.

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
- Keep the Content-Security-Policy working: Astro writes script and style hashes into each page
  (`security.csp` in `astro.config.mjs`), so no inline `style="…"` attributes and no external
  scripts, styles or fonts. nginx adds `frame-ancestors` and the other security headers.
- The status proxy resolves Uptime Kuma per request via the cluster DNS (`10.43.0.10`, the k3s
  default): nginx starts even when that name doesn't resolve. Change `resolver` if the cluster's
  service CIDR ever changes.
