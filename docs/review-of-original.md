# Review of the original `rpi5-k3s-homelab-guide.md`

This is the review that led to [`guide.md`](guide.md) and the manifests in this repository.
The original file is still at `../rpi5-k3s-homelab-guide.md`, unchanged.
Findings are ranked by impact, and each one says where the rewrite fixes it.

The core architecture was sound: k3s on a Pi 5, GitOps, a tunnel for public apps, and LAN/VPN for
DNS and media. The problems were in the details.

## Critical

| # | Finding | Fixed in |
|---|---|---|
| 1 | **Secrets committed in plaintext.** The tunnel token sat in a `Secret` in the GitOps repo, and Grafana's `adminPassword` was in Helm values. `papra-secrets` was referenced but never created, so the pod would never start. | Sealed Secrets + `scripts/secrets.sh`; Grafana `admin.existingSecret` |
| 2 | **"Jellyfin: full hardware-accelerated streaming" is false on the Pi 5.** It has no HW encoder, and Jellyfin has deprecated V4L2 on the Pi. | Direct-play plan, §11 |
| 3 | **Promtail** reached end of life on 2026-03-02. | Grafana Alloy + Loki single binary |
| 4 | **The RAM budget left out k3s itself, operators and Immich's dependencies.** Immich wasn't deployed at all (it needs Postgres + VectorChord, Valkey and ML; upstream minimum 6 GB). | Honest budget in §2; full Immich + CNPG manifests |

## Would not work as written

| # | Finding | Fixed in |
|---|---|---|
| 5 | A `ServiceMonitor` sat in the cloudflared bundle, but its CRD arrives later with kube-prometheus-stack, so the sync fails. | Sync waves + Application health check |
| 6 | The `networking` namespace was never created. | `apps/platform/namespaces.yaml` |
| 7 | The App-of-Apps `root-app.yaml` was referenced but never written. Argo CD was installed from a floating `stable` URL and wasn't self-managed. | `bootstrap/`, `argocd/00-argocd.yaml` |
| 8 | `:latest` on every image. | Pinned versions + Renovate |
| 9 | Vaultwarden `WEBSOCKET_ENABLED` has been obsolete since 1.29. `DOMAIN`, `SIGNUPS_ALLOWED=false` and `ADMIN_TOKEN` were missing. | `apps/security/vaultwarden` |
| 10 | Papra's volume was mounted at `/data`, but the app stores data in `/app/app-data`, so **data would be lost on restart**. | `apps/documents/papra` |
| 11 | `kube-prometheus-stack 61.*` was about 30 majors behind (91.x now). "The trap: retains metrics indefinitely" was wrong: the chart defaults to 10 d / 30 s. | Chart 91.8.1, `retentionSize` added, text corrected |
| 12 | "Cloudflare ToS Section 2.8" was removed in 2023. The restriction now sits in the CDN Service-Specific Terms. | §9 |
| 13 | "Configure tunnel health checks to use Request instead of Reply": no such Cloudflare setting exists. | Removed |
| 14 | `replicas: 2` cloudflared was sold as HA on a single node. | Honest comment, spread constraint, PDB |
| 15 | `--disable servicelb` leaves Traefik unreachable from the LAN. That breaks the guide's own advice to "upload big files on the LAN". | ServiceLB kept; AdGuard split-horizon + wildcard cert |
| 16 | `--write-kubeconfig-mode 644` makes cluster-admin credentials world-readable. | `0600` in `host/k3s-config.yaml` |

## Missing for a "production-grade" homelab

- NVMe boot, a cgroup **verification** step, journald caps, unattended-upgrades → §6
- k3s config file, embedded etcd + snapshots, kubelet reservations/eviction → `host/k3s-config.yaml`
- Concrete, **consistent** backups (not a raw file copy of live SQLite/Postgres): Vaultwarden
  `VACUUM INTO` snapshots, Postgres `pg_dump`, k8up restic to a second device (the SD card),
  restore drills → §13
- Sealed Secrets key backup and a whole-cluster rebuild procedure → §8, §13
- AdGuard manifest and DNS redundancy (the Pi is a single point of failure for the house) → §10
- Tailscale was mentioned but never set up → operator + Connector + split DNS
- Real client IPs through the tunnel (Traefik trusted IPs, `CF-Connecting-IP`) → §9
- Cloudflare Access scope: Access on all of Vaultwarden breaks the apps, so protect `/admin` only → §9
- An external dead-man's switch, since in-cluster Uptime Kuma can't report the cluster down → §12
- Pod Security Admission levels, `securityContext`, rootless images → all manifests
- SSD health and write-wear controls → §12

## Style

- Marketing language ("state-of-the-art", "enterprise", "battle-tested Reddit wisdom") was
  replaced with sourced statements.
- Section numbering jumped (5 → 7), and "Phases" overlapped with section numbers. Both are fixed.
- All six dashboard IDs exist on grafana.com. They're now pinned to their current revisions
  (the original pinned `revision: 1`, i.e. the oldest JSON). The AdGuard dashboard needs a separate
  exporter, so it was dropped.
