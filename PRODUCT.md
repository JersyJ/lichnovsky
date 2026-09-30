# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Currently Astro (static output) in `web/`, served by unprivileged nginx on the Pi. The owner explicitly allows a full rewrite from scratch, and Astro is not required. Whatever replaces it must keep the image contract in `web/README.md`: listen on 8080 as non-root with a read-only root filesystem, `GET /healthz` returns 200, `Cache-Control` headers set by `nginx.conf`, and the same-origin `/status-data/` proxy to Uptime Kuma. Deploy is push to `main` → GitHub Actions builds `ghcr.io/jersyj/lichnovsky-web` → Argo CD rolls it out.

## Users

- **Tech peers**: developers and homelab people who land on lichnovsky.eu and want to know who runs it, what it runs on, and how to reach Dominik.
- **Friends & family**: people who actually use the self-hosted services (passwords, documents, movies, later photos). They come to find the right link and see whether it works.

The owner also uses the page as a personal start page.

## Product Purpose

lichnovsky.eu is Dominik Lichnovsky's personal home page. It presents who Dominik is and works as a hub that sends visitors on to the self-hosted services. It shows each service's live availability, so a visitor knows whether a service is up before clicking through. Success means a peer leaves knowing who Dominik is and what Dominik built, and a friend reaches the right service in one click.

## Positioning

The page runs on the thing it presents: a homelab that Dominik built and operates (k3s on a Raspberry Pi 5, GitOps with Argo CD, Cloudflare Tunnel, Tailscale). The service list and the live status dots are real, current evidence of that work, not a portfolio description of it.

## Operating Context

- Visitors arrive by typing or following `lichnovsky.eu` (`www.` redirects), on desktop and phone.
- Services open on their own subdomains; the page links out to them.
- Availability comes from the public Uptime Kuma status page `home` (`/status-data/home` and `/status-data/heartbeat/home`), refreshed every 60 s. The full status page is `https://status.lichnovsky.eu/status/home`.
- Some services are public, some sit behind Cloudflare Access, and some are reachable only at home or over Tailscale.

## Capabilities and Constraints

- **Services (source of truth: `web/src/data/services.ts`)**:
  - Apps: Vaultwarden (passwords, `vault.`), Papra (documents, `papra.`), Jellyfin (movies & shows, `tv.`, home/Tailscale only).
  - Admin: Argo CD (deployments, `argocd.`), Grafana (metrics & logs, `grafana.`), Uptime Kuma (monitoring, `status.`), AdGuard Home (DNS & ad blocking, `dns.`, home/Tailscale only).
  - Planned: Immich (photos, `photos.`), not deployed yet.
- **All services are shown**, including admin and home-only ones, each labelled clearly so visitors understand which ones aren't for them (confirmed).
- **Availability stays minimal**: a small status dot per service (green up, red down, amber pending/maintenance), plus the existing one-line overall summary. No charts, uptime percentages or heavy status UI (confirmed).
- Adding a service must stay a single data entry.
- The site is static; the only runtime data is the status fetch. It must still read correctly when the status fetch fails.

## Brand Commitments

- Name: **Dominik Lichnovsky** (spelling from git; diacritics unconfirmed). Domain name as wordmark: `lichnovsky.eu`.
- One-line role: **DevOps / Platform engineer** (confirmed).
- Owner's brief for the look: clean and minimalistic, with a "wow" effect. If both can't live together, the wow effect can lead and the design form can change. This is a volunteered constraint and is recorded here without being expanded.

## Evidence on Hand

- Live service list and status data (above).
- The homelab itself, documented in `README.md` and `docs/architecture.md`: k3s on a Raspberry Pi 5, Argo CD GitOps, Cloudflare Tunnel, Tailscale, nightly encrypted backups, Discord alerts.
- Contact: GitHub `https://github.com/jersyj` (confirmed). No other links confirmed: no LinkedIn, no email on the page for now.
- **Absent, must not be fabricated**: photo/portrait, bio beyond the role line, CV, project list, employer, testimonials, uptime numbers or other metrics not read live.

## Product Principles

1. **Real over claimed.** Show the running system (live dots, real hosts) instead of describing skills.
2. **One click to the right place.** A friend finds their service and its state at a glance.
3. **Honest about access.** Never let a visitor click into a service they can't reach without telling them first.
4. **Minimal availability.** Status is one quiet signal per service, never a dashboard.
5. **One entry per service.** The page grows from data, not from hand-edited markup.

## Accessibility & Inclusion

No product-specific requirement stated. Status must not rely on colour alone: the dot's state is also exposed as text (title and summary line), as it is today.
