# web/

This folder contains the lichnovsky.eu start page. The page is an [Astro](https://docs.astro.build)
static site. nginx serves it. The Kubernetes manifests are in [apps/web](../apps/web).

```bash
npm install
npm run dev      # http://localhost:4321, with live status dots
npm run build    # dist/, the same files that go into the image
```

## Add a service

Add one entry in `src/data/services.ts`, on the Apps line or the Admin line:

- `access`: `public`, `sign-in` (Cloudflare Access) or `private` (home and Tailscale only)
- `monitor`: the name of the monitor on the Uptime Kuma status page `home`. This gives a live dot.
- `planned: true`: the map shows the service as not open yet.

## Deploy

1. Push to `main`.
2. CI builds `ghcr.io/jersyj/lichnovsky-web:sha-<commit>` and commits the tag to
   `apps/web/kustomization.yaml`. Argo CD then deploys the new image.
3. Before your next push, do `git pull --rebase`.

To go back to an earlier version, set `newTag` to an earlier tag.

## Technical notes

- The image runs as non-root on port 8080, with a read-only file system (`/tmp` only). It answers
  `GET /healthz`.
- `nginx.conf` sets `Cache-Control` and the security headers. Cloudflare caches according to
  `Cache-Control`.
- Astro adds a Content-Security-Policy with hashes of the inline code on the page. Thus, do not use
  inline `style="…"` attributes, and do not load files from other sites.
- The status proxy finds Uptime Kuma through the k3s DNS at `10.43.0.10` (`resolver` in
  `nginx.conf`).
