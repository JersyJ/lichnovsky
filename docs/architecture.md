# Architecture

This document tells you which components run, how requests get to them, and why we selected each
component. Read this document first. The installation steps are in [setup.md](setup.md). The daily
work is in [operations.md](operations.md).

## Overview

One Raspberry Pi 5 (8 GB, NVMe SSD) runs k3s. Argo CD deploys all components from this repository.
Thus, you make all changes in Git.

```
                               GitHub: JersyJ/lichnovsky (public)
                                            │  git push
                                            ▼
                                ┌────────────────────────┐
                                │ Argo CD (app of apps)  │  makes the cluster equal to Git
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
│   Media stack (LAN/Tailscale): Seerr ► Sonarr/Radarr ► Prowlarr ► qBittorrent ► /srv/media     │
│                                                                                                │
│   AdGuard Home (hostNetwork :53)       Tailscale operator (subnet router for 192.168.50.244/32)│
│   Prometheus · Alertmanager · Loki ◄── Alloy (pod logs)                                        │
│   Sealed Secrets · cert-manager · k8up (restic) ──► restic rest-server                         │
│                                                          │                                     │
│   NVMe SSD: app volumes, /srv/media     SD card 128 GB: /srv/backup (restic + etcd snapshots)  │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Three ways in, one set of URLs

Each app has one name, for example `https://vault.lichnovsky.eu`. The path depends on the location
of the client:

| Client | DNS answer | Path | Limits |
|---|---|---|---|
| Internet | Cloudflare (tunnel CNAME) | Cloudflare edge → tunnel → cloudflared → Traefik | 100 MB request body. No video streaming. |
| Home LAN | AdGuard rewrite → `192.168.50.244` | Directly to Traefik | None |
| Tailscale | Split DNS → AdGuard → `192.168.50.244` | Tailnet → subnet router → Traefik | None |

Traefik has a Let's Encrypt wildcard certificate. The certificate uses DNS-01, thus no port must be
open. HTTPS operates the same on all paths. The Bitwarden apps and the Vaultwarden web vault must
have HTTPS. Traefik redirects plain `http://` to HTTPS. Tunnel traffic also arrives on port 80.
cloudflared sends `X-Forwarded-Proto: https`, thus Traefik does not redirect it in a loop.

The [README](../README.md) shows which apps are public and which apps are behind Cloudflare Access.
Private names have no public DNS record. They are only AdGuard rewrites.

**Access controls only the internet path.** At home and through Tailscale, requests go directly to
Traefik. Thus, each app must use its own login. Sign-up is closed in all apps, and each app has one
admin.

Jellyfin is private, because the CDN terms of Cloudflare do not permit video from your own server
through the CDN. The tunnel is part of the CDN.

## Stack

| Area | Component | Reason |
|---|---|---|
| Kubernetes | **k3s** (embedded etcd) | One binary with Traefik, ServiceLB and local-path storage. etcd uses approximately 150 MB more than SQLite. It gives snapshots and lets you add control-plane nodes. |
| GitOps | **Argo CD**, which also manages itself | UI, app of apps, drift detection and self-heal |
| Secrets | **Sealed Secrets** | Encrypted Secrets that are safe in Git. No other service is necessary. |
| Certificates | **cert-manager** + Let's Encrypt DNS-01 | Wildcard certificate for HTTPS on the LAN and Tailscale. No open port. |
| Public ingress | **Cloudflare Tunnel** | No open ports. It operates behind CGNAT. WAF and Access are in front. |
| Cloudflare configuration | **OpenTofu** (`cloudflare/`), state encrypted in R2 | You can review the tunnel, DNS, Access, rules and DNSSEC in Git. |
| Remote access | **Tailscale operator** | Private access at full speed (Jellyfin, large uploads) |
| DNS | **AdGuard Home** | Ad blocking for the house and split-horizon DNS for the app names |
| Passwords | **Vaultwarden** | Compatible with Bitwarden and very small |
| Documents | **Papra** | Simple document archive with a rootless image |
| Media | **Jellyfin**, direct play | The Pi 5 has no hardware video encoder. Thus, the media must play without transcoding. |
| Media automation | **Seerr**, **Sonarr**, **Radarr**, **Prowlarr**, **qBittorrent**, **Bazarr**, **FlareSolverr** | For a request in Seerr, the stack searches, downloads, renames and adds subtitles. Then the title is in Jellyfin. The images are from home-operations: rootless and made for Kubernetes. |
| Media settings as code | **Configarr** (CronJob, each hour) | Applies from Git: TRaSH-Guides quality profiles and naming, root folders, the download client and the app links of Prowlarr. It does all that Recyclarr does, and more. Buildarr has no maintenance. Notifiarr keeps its configuration on its website. |
| Metrics, alerts | **kube-prometheus-stack** → Discord | Prometheus, Grafana, Alertmanager, node-exporter |
| Logs | **Loki** (single binary) + **Alloy** | Alloy replaces Promtail (end of life 2026-03-02) |
| Uptime | **Uptime Kuma** | Checks from the inside, and the public status page |
| Heartbeat | **Cloudflare Worker** (each 5 minutes) | Sees from the outside when the full Pi is unavailable |
| Backups | **k8up** (restic) → **restic rest-server** on the SD card | Encrypted, deduplicated snapshots each night, on a second device |
| Website | **Astro**, built by GitHub Actions into an nginx image (`web/`) | Static pages use few resources on the Pi, and Cloudflare caches them fully. Source, build and deployment are in one repository. |
| Updates | **Renovate** | Pull requests for new chart and image versions. When you merge a pull request, Argo CD deploys it. |

The manifests pin all versions. Renovate keeps them current.

**Not used, on purpose:** On one or two Pis, distributed storage (Longhorn, Ceph) costs more RAM
and SSD wear than it saves. Home Assistant operates better on its own device (HAOS).

## Memory

The Pi has 7.9 GB. Before the media stack, approximately **5.1 GB** was in use (`free -m`, without
page cache). The largest users:

- k3s (API server and etcd): approximately 1.3 GB
- Grafana, with its plugin processes: approximately 350 MB
- Prometheus: approximately 340 MB
- The Argo CD controller: approximately 320 MB
- Papra: approximately 300 MB

These settings keep the memory use low:

- `GOMEMLIMIT=1300MiB` for k3s (`host/k3s-memory.conf`). Without it, Go lets the heap grow to
  approximately 2× its live data. This setting decreased k3s from 1.8 GB to 1.3 GB.
- `GOMEMLIMIT=650MiB` for the Argo CD controller. Its cache also excludes resource types that change
  frequently (Events, ACME orders). Refer to `bootstrap/argocd-values.yaml`.
- The kubelet reserves 768 Mi. If less than 256 Mi is free, the kubelet evicts pods
  (`host/k3s-config.yaml`). Thus, at a peak, one pod restarts and the Pi does not freeze.

**The media stack** uses approximately 1.2 GB at idle (measured):

- Sonarr, Radarr, Prowlarr, Bazarr, Seerr: approximately 170–200 MB each
- FlareSolverr: approximately 250 MB, and more while Chrome runs
- qBittorrent: approximately 25 MB without active downloads

**Immich operates without machine learning** when you enable it. It uses approximately 0.7–0.9 GB
at idle and 1.5–2 GB during a large import. With the media stack, the memory is tight. To get
memory, first remove FlareSolverr. The machine-learning models of Immich need 1–1.5 GB more, which
is more than is free. Refer to [operations.md → Enable Immich](operations.md#enable-immich).

## Kubernetes structure

Each app is **one YAML file with several resources**, separated by `---` (Deployment, Service,
Ingress). Kubernetes recommends this for related objects. All parts of an app are in one location,
and you apply them together.

Two apps are different:

- The website (`apps/web/`) has one file for each resource and uses Kustomize. CI writes each new
  image tag into the `images:` field.
- The media stack (`apps/media/`) is one Argo CD app with one file for each program.

**Namespaces:** Platform components use names for their function (`networking`, `monitoring`,
`tailscale`, `backups`). Apps use `web`, `vaultwarden`, `papra`, `dns` (AdGuard), `tv` and
`photos` (Immich). Jellyfin and the media stack share the namespace `tv`, because they share the
media volume. Uptime Kuma is in `monitoring`.

A SealedSecret is encrypted for one namespace and one name. If you move an app to a different
namespace, you must seal its secrets again.

### Sync order

Argo CD applies the Applications wave by wave. Each wave must be *Healthy* before the next wave
starts. `bootstrap/argocd-values.yaml` adds the Application health check that makes this possible.

| Wave | Applications | Reason |
|---|---|---|
| -10 | `argocd` | Manages its own upgrades |
| -9 | `sealed-secrets`, `cert-manager` | All later waves need secrets or certificates |
| -8 | `platform` | Namespaces, infrastructure secrets, ClusterIssuer, wildcard certificate, Traefik configuration |
| -7 | `kube-prometheus-stack`, `k8up`, `tailscale-operator` (+ `cloudnative-pg`) | Install the CRDs that later apps use |
| -6 | `loki`, `tailscale-config` | Need the Tailscale CRDs. Alloy needs Loki. |
| -5 | `alloy` | Needs Loki |
| 0 | All apps | |
| 1 | `backups` | Needs the k8up CRDs and the volumes of the apps |

`scripts/validate.py` makes sure of this order. For each custom resource in an enabled app, an
enabled chart or k3s must install its CRD.

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
