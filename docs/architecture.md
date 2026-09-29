# Architecture

What runs, how requests reach it, and why each piece was chosen. Read this first; the step-by-step
build is in [setup.md](setup.md), day-to-day work in [operations.md](operations.md).

## Overview

One Raspberry Pi 5 (8 GB, NVMe SSD) runs k3s. Argo CD deploys everything from this repo, so Git is
the only place anything is changed.

```
                               GitHub: JersyJ/lichnovsky (private)
                                            │  git push
                                            ▼
                                ┌────────────────────────┐
                                │ Argo CD (app of apps)  │  reconciles Git -> cluster
                                └───────────┬────────────┘
                                            │
 Internet ──► Cloudflare edge ──► Tunnel    │     Home LAN ─────────────┐   Tailscale (anywhere)
 (WAF, Access SSO, TLS)          (outbound) │     (AdGuard answers      │   (split DNS lichnovsky.eu
              │                             │      app names with       │    -> 192.168.50.244)
              │                             │      192.168.50.244)      │          │
┌─────────────┼─────────────────────────────┼───────────────────────────┼──────────┼─────────────┐
│ rpi-01  k3s ▼                             ▼                           ▼          ▼             │
│   cloudflared x2 ──► Traefik ClusterIP :80    Traefik on node IP :80/:443 (ServiceLB)          │
│                          │                     wildcard *.lichnovsky.eu cert (cert-manager)    │
│                          └───────────────┬─────────────┘                                       │
│                                          ▼                                                     │
│   Website · Vaultwarden · Papra · Uptime Kuma · Grafana · Argo CD · Jellyfin (LAN/Tailscale)   │
│                                                                                                │
│   AdGuard Home (hostNetwork :53)       Tailscale operator (subnet router for 192.168.50.244/32)│
│   Prometheus · Alertmanager · Loki ◄── Alloy (pod logs)                                        │
│   Sealed Secrets · cert-manager · k8up (restic) ──► restic rest-server                         │
│                                                          │                                     │
│   NVMe SSD: app volumes, /srv/media     SD card 128 GB: /srv/backup (restic + etcd snapshots)  │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Three ways in, one set of URLs

Every app has one name, e.g. `https://vault.lichnovsky.eu`. The path depends on where the client is:

| Client | DNS answer | Path | Limits |
|---|---|---|---|
| Internet | Cloudflare (tunnel CNAME) | Cloudflare edge → tunnel → cloudflared → Traefik | 100 MB request body; no video streaming |
| Home LAN | AdGuard rewrite → `192.168.50.244` | straight to Traefik | none |
| Tailscale | split DNS → AdGuard → `192.168.50.244` | tailnet → subnet router → Traefik | none |

Traefik serves a Let's Encrypt wildcard certificate (DNS-01, so no inbound port), so HTTPS works
the same on every path. The Bitwarden apps and Vaultwarden's web vault require it; plain `http://`
is redirected. Tunnel traffic also arrives on port 80, but cloudflared sends
`X-Forwarded-Proto: https`, so it isn't redirected in a loop.

Which apps are public and which sit behind Cloudflare Access is in the [README](../README.md).
Private names have no public DNS record; they exist only as AdGuard rewrites.
**Access only covers the internet path.** At home and on Tailscale, requests go straight to
Traefik, so every app relies on its own login: sign-ups are closed everywhere and each app has a
single admin.

Jellyfin is private because Cloudflare's CDN terms forbid serving video from your own origin
through the CDN, and the tunnel counts.

## Stack

| Area | Component | Why this one |
|---|---|---|
| Kubernetes | **k3s** (embedded etcd) | Single binary with Traefik, ServiceLB, local-path storage built in. etcd (~150 MB more than SQLite) gives snapshots and room for more control-plane nodes |
| GitOps | **Argo CD**, manages itself | UI, app of apps, drift detection and self-heal |
| Secrets | **Sealed Secrets** | Encrypted Secrets safe to commit; nothing else to run |
| Certificates | **cert-manager** + Let's Encrypt DNS-01 | Wildcard cert for LAN/Tailscale HTTPS, no open port |
| Public ingress | **Cloudflare Tunnel** | No open ports, works behind CGNAT, WAF and Access in front |
| Cloudflare config | **OpenTofu** (`cloudflare/`), state encrypted in R2 | Tunnel, DNS, Access, rules and DNSSEC reviewable in Git |
| Remote access | **Tailscale operator** | Full-speed private access (Jellyfin, big uploads) |
| DNS | **AdGuard Home** | Ad blocking for the house + split-horizon DNS for the app names |
| Passwords | **Vaultwarden** | Bitwarden-compatible and tiny |
| Documents | **Papra** | Simple document archive with a rootless image |
| Media | **Jellyfin**, direct play | The Pi 5 has no hardware video encoder, so media must play without transcoding |
| Metrics, alerts | **kube-prometheus-stack** → Discord | Prometheus, Grafana, Alertmanager, node-exporter |
| Logs | **Loki** (single binary) + **Alloy** | Alloy replaces Promtail (end of life 2026-03-02) |
| Uptime | **Uptime Kuma** | Checks from inside + the public status page |
| Heartbeat | **Cloudflare Worker** (every 5 min) | Notices from outside when the whole Pi is gone |
| Backups | **k8up** (restic) → **restic rest-server** on the SD card | Encrypted, deduplicated nightly snapshots on a second device |
| Updates | **Renovate** | PRs for new chart and image versions; merging deploys them |

Versions are pinned in the manifests; Renovate keeps them current.

**Left out on purpose:** distributed storage (Longhorn/Ceph) costs more RAM and SSD wear than it
saves on one or two Pis. Home Assistant runs better on its own device (HAOS).

## Memory

About **5.1 GB used, 2.9 GB available** of 7.9 GB with everything running (`free -m`, page cache
excluded). The biggest consumers: k3s itself (API server + etcd, ~1.3 GB), Grafana (~350 MB with its
plugin processes), Prometheus (~340 MB), Argo CD's controller (~320 MB), Papra (~300 MB).

What keeps it there:
- `GOMEMLIMIT=1300MiB` for k3s (`host/k3s-memory.conf`): Go otherwise lets the heap grow to ~2× its
  live data. This took k3s from ~1.8 GB to ~1.3 GB.
- `GOMEMLIMIT=650MiB` for Argo CD's controller, and high-churn resource types (Events, ACME orders)
  excluded from its cache (`bootstrap/argocd-values.yaml`).
- The kubelet reserves 768 Mi and evicts pods below 256 Mi free (`host/k3s-config.yaml`), so a busy
  moment restarts one pod instead of freezing the Pi.

**Immich runs without machine learning** when enabled: ~0.7–0.9 GB at idle and ~1.5–2 GB during a
big import fit; its ML models would add another 1–1.5 GB and use up everything that's free. See
[operations.md → Enabling Immich](operations.md#enabling-immich).

## Kubernetes structure

Each app is **one YAML file with several resources** separated by `---` (Deployment, Service,
Ingress…). That's standard Kubernetes practice: everything that belongs to an app is in one place and
applied together.

**Namespaces:** platform pieces use functional names (`networking`, `monitoring`, `tailscale`,
`backups`); apps use `web`, `vaultwarden`, `papra`, `dns` (AdGuard), `tv` (Jellyfin), `photos` (Immich).
Uptime Kuma lives in `monitoring`. A SealedSecret is encrypted for one namespace + name, so moving an
app to another namespace means re-sealing its secrets.

### Sync order

Argo CD applies Applications wave by wave, and each wave must be *Healthy* before the next starts
(`bootstrap/argocd-values.yaml` adds the Application health check that makes this work).

| Wave | Applications | Why |
|---|---|---|
| -10 | `argocd` | manages its own upgrades |
| -9 | `sealed-secrets`, `cert-manager` | everything after needs secrets or certificates |
| -8 | `platform` | namespaces, infrastructure secrets, ClusterIssuer, wildcard cert, Traefik config |
| -7 | `kube-prometheus-stack`, `k8up`, `tailscale-operator` (+ `cloudnative-pg`) | install the CRDs later apps use |
| -6 | `loki`, `tailscale-config` | need Tailscale CRDs; Alloy needs Loki |
| -5 | `alloy` | needs Loki |
| 0 | all apps | |
| 1 | `backups` | needs k8up CRDs and the apps' volumes |

`scripts/validate.py` enforces this: every custom resource in an enabled app must have its CRD
installed by an enabled chart or by k3s.

## References

- k3s: https://docs.k3s.io · HelmChartConfig: https://docs.k3s.io/helm
- Argo CD sync waves: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- Sealed Secrets: https://github.com/bitnami/sealed-secrets
- Alloy (Promtail migration): https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/
- Cloudflare CDN terms on video: https://blog.cloudflare.com/updated-tos/
- Jellyfin hardware acceleration: https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/
- Tailscale operator: https://tailscale.com/kb/1236/kubernetes-operator
- k8up: https://docs.k8up.io · restic rest-server: https://github.com/restic/rest-server
- OpenTofu state encryption: https://opentofu.org/docs/language/state/encryption/
