# web/

The lichnovsky.eu start page: an [Astro](https://docs.astro.build) static site served by nginx.
Kubernetes side: [apps/web](../apps/web).

```bash
npm install
npm run dev      # http://localhost:4321, live status dots included
npm run build    # dist/, exactly what gets deployed
```

## Adding a service

One entry in `src/data/services.ts`, on the Apps or Admin line:

- `access`: `public`, `sign-in` (Cloudflare Access) or `private` (home and Tailscale only)
- `monitor`: its name on the Uptime Kuma status page `home`, for a live dot
- `planned: true`: shown as not open yet

## Deploy

Push to `main`. CI builds `ghcr.io/jersyj/lichnovsky-web:sha-<commit>`, commits the tag to
`apps/web/kustomization.yaml`, and Argo CD rolls it out. Then `git pull --rebase` before your next
push. To roll back, set `newTag` to an earlier tag.

## Keep in mind

- The image runs as non-root on port 8080 with a read-only filesystem (`/tmp` only) and answers
  `GET /healthz`.
- `nginx.conf` sets `Cache-Control` (Cloudflare caches by it) and the security headers.
- Astro adds a Content-Security-Policy with hashes of the page's inline code: no inline `style="…"`
  attributes, and nothing loaded from other sites.
- The status proxy looks up Uptime Kuma through the k3s DNS at `10.43.0.10` (`resolver` in
  `nginx.conf`).
