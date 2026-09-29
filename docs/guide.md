# lichnovsky.eu: Raspberry Pi 5 Kubernetes Homelab

A self-hosted personal cloud and the lichnovsky.eu website on one Raspberry Pi 5 (8 GB, NVMe SSD),
managed with GitOps from this repository and published through Cloudflare Tunnel with no ports
open on the router. Backups go to a second device in the Pi (the SD card for now), so there are no
cloud storage costs. A second Pi can join later.

> **Checked:** 2026-09-28. All chart and image versions in this repo were read from upstream
> registries on that date. Renovate (see [Day-2](#12-day-2-operations)) keeps them current.

---

## Contents

1. [Architecture](#1-architecture)
2. [Stack and RAM budget](#2-stack-and-ram-budget)
3. [Hostnames and exposure](#3-hostnames-and-exposure)
4. [Repository layout, sync order and staged rollout](#4-repository-layout-sync-order-and-staged-rollout)
5. [Phase 0: Accounts and prerequisites](#5-phase-0-accounts-and-prerequisites)
6. [Phase 1: Hardware and OS](#6-phase-1-hardware-and-os)
7. [Phase 2: k3s](#7-phase-2-k3s)
8. [Phase 3: Argo CD bootstrap and secrets](#8-phase-3-argo-cd-bootstrap-and-secrets)
9. [Phase 4: Cloudflare Tunnel and Access (as code)](#9-phase-4-cloudflare-tunnel-and-access-as-code)
10. [Phase 5: LAN and remote access (AdGuard + Tailscale)](#10-phase-5-lan-and-remote-access)
11. [Phase 6: First run of each app](#11-phase-6-first-run-of-each-app)
12. [Day-2 operations](#12-day-2-operations)
13. [Backups and disaster recovery](#13-backups-and-disaster-recovery)
14. [Adding a second Raspberry Pi](#14-adding-a-second-raspberry-pi)
15. [Known pitfalls](#15-known-pitfalls)
16. [References](#16-references)

---

## 1. Architecture

```
                               GitHub: JersyJ/lichnovsky (private repo)
                                            │  git push
                                            ▼
                                ┌────────────────────────┐
                                │ Argo CD (app of apps)  │  reconciles Git -> cluster
                                └───────────┬────────────┘
                                            │
 Internet ──► Cloudflare edge ──► Tunnel    │     Home LAN ─────────────┐   Tailscale (anywhere)
 (WAF, Access SSO, TLS)          (outbound) │     (AdGuard answers      │   (split DNS lichnovsky.eu
              │                             │      app names with       │    -> 192.168.50.244)
              │                             │      192.168.50.244)       │          │
┌─────────────┼─────────────────────────────┼──────────────────────────┼──────────┼──────────────┐
│ rpi-01  k3s  ▼                             ▼                          ▼          ▼              │
│   cloudflared x2 ──► Traefik ClusterIP :80    Traefik on node IP :80/:443 (ServiceLB)          │
│                          │                     wildcard *.lichnovsky.eu cert (cert-manager)    │
│                          └───────────────┬─────────────┘                                       │
│                                          ▼                                                     │
│   Website (lichnovsky.eu) · Vaultwarden · Papra · Immich (+CNPG Postgres, Valkey, ML)          │
│   Uptime Kuma · Grafana · Argo CD · Jellyfin (LAN/Tailscale only)                              │
│                                                                                                │
│   AdGuard Home (hostNetwork :53)       Tailscale operator (subnet router for 192.168.50.244/32) │
│   Prometheus · Alertmanager · Loki ◄── Alloy (pod logs)                                        │
│   Sealed Secrets · cert-manager · CloudNativePG · k8up (restic) ──► restic rest-server         │
│                                                                    │                           │
│   NVMe SSD: local-path PVs, /srv/media    SD card 128 GB: /srv/backup ◄┘ (restic + etcd snaps) │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
```

**Three ways in, one set of URLs.** Every app has one name, such as `https://photos.lichnovsky.eu`.
Which path a request takes depends on where the client is:

| Client location | DNS answer | Path | Limits |
|---|---|---|---|
| Internet | Cloudflare (tunnel CNAME) | Cloudflare edge → tunnel → cloudflared → Traefik | 100 MB request body (Free plan); video streaming not allowed |
| Home LAN | AdGuard rewrite → `192.168.50.244` | Straight to Traefik on the Pi | None |
| Tailscale | Split DNS → AdGuard → `192.168.50.244` | Tailnet → subnet router → Traefik | None |

On the LAN and over Tailscale, Traefik serves a real Let's Encrypt wildcard certificate, obtained
through a DNS-01 challenge so no port has to be open. That means HTTPS works the same everywhere,
which the Bitwarden and Immich apps need.

**What isn't here, on purpose:**
- **Home Assistant.** Planned for later. It usually runs better on its own device (HAOS) than in k3s.
- **Distributed storage (Longhorn/Ceph).** Not worth it on one or two Pis; see [§14](#14-adding-a-second-raspberry-pi).

---

## 2. Stack and RAM budget

| Area | Component | Why this one | Version |
|---|---|---|---|
| Distro | **k3s** (embedded etcd) | Small single binary with Traefik, ServiceLB, local-path storage and CoreDNS built in | v1.36.4+k3s1 |
| GitOps | **Argo CD** (Helm, manages itself) | UI, app-of-apps, drift detection. Flux is lighter; Argo CD is easier to learn from | chart 10.9.2 / v3.5.3 |
| Secrets | **Sealed Secrets** | Encrypted Secrets safe to commit; nothing else to operate | chart 2.20.0 / v0.40.0 |
| Certificates | **cert-manager** + Let's Encrypt DNS-01 | Wildcard cert for LAN/Tailscale HTTPS | v1.20.4 |
| Public ingress | **Cloudflare Tunnel** | No open ports, works behind CGNAT, WAF + Access SSO in front | 2026.9.3 |
| Remote access | **Tailscale operator** | Full-speed private access (Jellyfin, big uploads) | 1.102.4 |
| DNS | **AdGuard Home** | Ad blocking + split-horizon DNS for the app names | v0.107.79 |
| Passwords | **Vaultwarden** | Bitwarden-compatible, tiny | 1.37.3 |
| Documents | **Papra** | Simple document archive; rootless image | 26.6.2 |
| Photos | **Immich** (future stage, not deployed yet) | Google Photos replacement | v3.2.2 |
| Postgres | **CloudNativePG** + VectorChord image (with Immich) | Declarative Postgres; nightly `pg_dump` for backups | chart 0.29.1 / 1.30.1 |
| Media | **Jellyfin** (LAN/Tailscale, direct play) | Open source. The Pi 5 has **no HW encoder**, see §11 | 12.1 |
| Metrics | **kube-prometheus-stack** | Prometheus Operator, Grafana, Alertmanager, node-exporter, KSM | 91.8.1 |
| Logs | **Loki** (single binary) + **Grafana Alloy** | Alloy replaces Promtail, which reached EOL on 2026-03-02 | 7.3.0 / 1.13.0 |
| Uptime | **Uptime Kuma** 2.x | Internal checks + a public status page | 2.5.5 |
| Heartbeat | **Cloudflare Worker** (cron, every 5 min) | Notices from outside when the whole Pi is unreachable; posts to Discord | – |
| Backups | **k8up** (restic) → **restic rest-server** on the SD card | Encrypted, deduplicated nightly snapshots on a second device; no cloud bill | 4.10.0 / 0.14.0 |
| Website | **nginx-unprivileged** placeholder with a live status widget, to be replaced by your own image | Served from the Pi through the tunnel | 1.31.6 |
| Updates | **Renovate** | Opens PRs for new chart/image versions; you merge, Argo CD deploys | - |

### Memory: measured on the Pi (not estimates)

Measured with `free -m` after each stage went live (7.9 GB total). "Used" excludes page cache:

| After stage | Used | Available | What the stage added |
|---|---|---|---|
| 1 Foundation (k3s, Argo CD, Sealed Secrets, cert-manager, cloudflared, website) | 2.2 GB | 5.9 GB | – |
| 2 Observability (Prometheus, Grafana, Alertmanager, Loki, Alloy) | 4.45 GB → **3.7 GB** after tuning | 3.6 → **4.3 GB** | ~1.5 GB |
| 3 Vaultwarden, AdGuard, Tailscale, backups | 4.2 GB | 3.9 GB | ~0.5 GB |
| 4 Papra, Uptime Kuma | 4.95 GB | 3.1 GB | ~0.45 GB |
| 5 Jellyfin (idle / direct play) | ~5.0 GB | 3.1 GB | small at idle |

The biggest single consumers: **k3s-server** (API server + etcd, ~1.3 GB), **Grafana** (~350 MB with
its plugin processes), **Prometheus** (~340 MB), **Argo CD's controller** (~320 MB), **Papra** (~300 MB).

What got the stage-2 number down (see `host/k3s-memory.conf`, `bootstrap/argocd-values.yaml`):
- `GOMEMLIMIT=1300MiB` for k3s (a systemd drop-in): Go collects garbage harder instead of letting the
  heap grow to ~2× its live data. k3s went from ~1.8 GB to ~1.3 GB.
- `GOMEMLIMIT=650MiB` for Argo CD's controller, and Events / ACME / k3s-internal types excluded
  from its cache.
- The install-time peak of the big Prometheus CRDs settles by itself within an hour.

**For Immich (the future stage):** CNPG + Postgres + Immich server + ML add ~1.3 GB at idle and up
to ~3 GB during the first import. With ~3 GB available that's tight: lower Immich's job concurrency
(Administration → Jobs), import in batches, and watch the memory alert. If it's still tight, move
Immich ML to a second Pi first (its manifest has the node affinity ready), or turn ML off.

The kubelet reserves 768 Mi and evicts pods below 256 Mi free (`host/k3s-config.yaml`), so a busy
moment restarts one pod instead of freezing the whole Pi.

---

## 3. Hostnames and exposure

| Hostname | App | Public (tunnel) | Cloudflare Access | LAN / Tailscale |
|---|---|---|---|---|
| `lichnovsky.eu` | Website | yes | no | yes |
| `www.lichnovsky.eu` | 301 → `lichnovsky.eu` | yes | no | yes |
| `vault.lichnovsky.eu` | Vaultwarden | yes | only on `/admin` | yes |
| `photos.lichnovsky.eu` | Immich | yes | no (breaks mobile app + share links) | yes |
| `papra.lichnovsky.eu` | Papra | yes | yes (email OTP / GitHub) | yes |
| `status.lichnovsky.eu` | Uptime Kuma | yes | yes for the admin UI; **bypass** for the public status page `/status/home` and its data | yes |
| `argocd.lichnovsky.eu` | Argo CD | yes | **yes, required** | yes |
| `grafana.lichnovsky.eu` | Grafana | yes | **yes, required** | yes |
| `tv.lichnovsky.eu` | Jellyfin | **no** | - | yes |
| `dns.lichnovsky.eu` | AdGuard UI | **no** | - | yes |

Private names never get a public DNS record. They only exist as AdGuard rewrites, and Tailscale
reaches them through split DNS.

**Cloudflare Access only applies to the internet path.** At home and over Tailscale, requests go
straight to Traefik, so each app is protected by its own login there. That's why sign-ups are closed
everywhere (Vaultwarden invitations only, Papra `AUTH_IS_REGISTRATION_ENABLED=false`, a single
admin in Uptime Kuma / Grafana / Argo CD / AdGuard). Plain `http://` is redirected to `https://` by
Traefik (`platform/cluster/traefik/redirect-https.yaml`); tunnel traffic passes through without a
loop, because cloudflared sends `X-Forwarded-Proto: https`.

---

## 4. Repository layout, sync order and staged rollout

```
lichnovsky/                    # github.com/JersyJ/lichnovsky
├── bootstrap/
│   ├── argocd-values.yaml     # Argo CD Helm values (used by bootstrap AND by Argo CD itself)
│   └── root.yaml              # the only thing you kubectl-apply: syncs argocd/
├── argocd/                    # ENABLED Applications (stage 1); sync-wave sets the order
│   └── later/stage-2…5/       # not deployed yet: move files up into argocd/ one stage at a time
├── platform/                  # keeps the cluster running; namespaces named by FUNCTION
│   ├── cluster/               # namespaces (PSA), Traefik config, TLS, ClusterIssuer, infra secrets
│   ├── cloudflared/           # tunnel connector (namespace networking)
│   ├── monitoring/            # ServiceMonitors + alert rules (namespace monitoring)
│   ├── tailscale/             # Connector (subnet router)
│   └── backups/               # restic rest-server on the SD card + k8up Schedules
├── apps/                      # what you use; one folder per app (= its Argo CD app name)
│   └── website/  vaultwarden/  adguard/  papra/  uptime-kuma/  immich/  jellyfin/
├── cloudflare/                # OpenTofu: tunnel, DNS, Access, rules, zone settings (state in R2)
├── host/                      # files that go on the Pi itself (k3s config, journald cap)
├── scripts/
│   ├── seal.sh                # create one SealedSecret; plaintext never touches the disk
│   └── validate.py            # helm-render every chart + kubeconform + stage check, offline
├── .pre-commit-config.yaml    # git hooks, run with prek
├── renovate.json
└── docs/guide.md              # this file
```

**Sync waves.** Within whatever is enabled, Argo CD applies these in order, and each wave must be
*Healthy* before the next starts. (`bootstrap/argocd-values.yaml` adds the Application health check that makes an
app-of-apps actually wait.)

| Wave | Applications | Why this order |
|---|---|---|
| -10 | `argocd` | Argo CD manages its own upgrades |
| -9 | `sealed-secrets`, `cert-manager` | Everything after needs secrets or certificates |
| -8 | `platform` | Namespaces, infra SealedSecrets, ClusterIssuer, wildcard cert, Traefik config |
| -7 | `kube-prometheus-stack`, `cloudnative-pg`, `k8up`, `tailscale-operator` | Install CRDs (ServiceMonitor, Cluster, Schedule, Connector) |
| -6 | `loki`, `tailscale-config` | Need Tailscale CRDs; Alloy needs Loki |
| -5 | `alloy` | Needs Loki |
| 0 | all apps | |
| 1 | `backups` | rest-server + Schedules; needs k8up CRDs and the apps' PVCs |

### Staged rollout
The RAM figures in §2 are estimates until measured on your Pi, so the cluster is brought up in
five stages. The root app only syncs the files **directly** in `argocd/`. Everything under
`argocd/later/` is dormant until you move it up (`argocd/later/README.md` has the exact commands):

| Stage | What gets enabled | Before moving on |
|---|---|---|
| **1 Foundation** (enabled from the start) | Argo CD, Sealed Secrets, cert-manager, platform, cloudflared, website placeholder | https://lichnovsky.eu loads; wildcard cert `Ready` |
| **2 Observability** | kube-prometheus-stack, Loki, Alloy, monitors, Discord alerts | a test alert reaches Discord; note the baseline RAM for a few days |
| **3 Critical apps + backups** | Vaultwarden, AdGuard + Tailscale, k8up + rest-server | first nightly backup succeeds, then **do a restore test** (§13) |
| **4 Lighter apps** | Papra, Uptime Kuma | RAM still comfortable |
| **5 Media** | Jellyfin | direct play works at home and over Tailscale |
| **6 Immich** (future, `later/stage-5-immich`) | CloudNativePG + Immich | import photos in batches at low job concurrency; watch memory. If RAM is tight, move Immich ML to a second Pi first |

Enabling a stage: `git mv argocd/later/stage-2-observability/*.yaml argocd/ && git commit -m "feat: stage 2" && git push`.
Nothing in an early stage depends on a CRD from a later one (for example, cloudflared's
ServiceMonitor lives with the stage-2 monitors), and `scripts/validate.py` enforces that.

### Checks and git hooks
- **`scripts/validate.py`** renders every chart (all stages) with its pinned version and values,
  validates the ~400 resources, CRDs included, with kubeconform, and runs the **stage check**:
  any custom resource in an *enabled* app must have its CRD installed by an enabled chart or by k3s.
  It needs `uv`, `helm` and `kubeconform` on `PATH`.
- **Git hooks with [prek](https://github.com/j178/prek)** (`.pre-commit-config.yaml`):
  ```bash
  prek install               # installs pre-commit and pre-push hooks
  ```
  - On every commit: whitespace/EOF fixes, YAML/JSON syntax, merge markers, large files, private
    keys, yamllint, gitleaks, and a **plaintext-Secret guard**. The guard rejects any
    `kind: Secret` in a YAML file (a `pygrep` rule, no script).
  - On every push: `scripts/validate.py` (slow: it downloads charts and schemas).

---

## 5. Phase 0: Accounts and prerequisites

1. **Domain on Cloudflare.** Registrar (e.g. Porkbun) stays; only the nameservers move:
   Cloudflare → *Connect a domain* → Free plan. Delete the registrar's parking records (`*`/`www`
   CNAMEs, `_acme-challenge` TXTs) during the import. **Turn DNSSEC off at the registrar first**, or
   the domain stops resolving after the nameserver switch. At Porkbun that switch is tied to its own
   nameservers, so using its "connect to Cloudflare" option is the easy path. TLS settings, DNSSEC
   and everything else are then managed as code (Phase 4).
2. **Cloudflare API token for cert-manager** (manual on purpose): My Profile → API Tokens →
   template *Edit zone DNS*, zone `lichnovsky.eu` only. The OpenTofu bootstrap (R2 bucket,
   OpenTofu token, Zero Trust team) is in `cloudflare/README.md`; see Phase 4.
3. **Tailscale account** (free Personal plan; log in with Google/GitHub/…). Admin console →
   **Access controls** → add to the policy file (keep the rest):
   ```jsonc
   "tagOwners": {
     "tag:k8s-operator": ["autogroup:admin"],
     "tag:k8s": ["tag:k8s-operator"],
   },
   "autoApprovers": {
     "routes": { "192.168.50.244/32": ["tag:k8s"] },
   },
   ```
   Then **Settings → Trust credentials** → new OAuth client with scopes *General → Services*,
   *Devices → Core*, *Keys → Auth Keys* (each Read + Write) and tag `tag:k8s-operator`.
   Scopes change between releases; check the [operator quickstart](https://tailscale.com/docs/kubernetes-operator/quickstart).
4. **Private GitHub repo** `JersyJ/lichnovsky`. Push this folder to it, then replace every
   `CHANGEME` (`grep -rn CHANGEME .`):
   - `git@github.com:JersyJ/lichnovsky.git` → your repo URL (in `bootstrap/root.yaml` and `argocd/*.yaml`):
     `grep -rl 'github.com/JersyJ/' . | xargs sed -i 's#github.com/JersyJ/#github.com/<your-user>/#'`
   - `192.168.50.244` → the Pi's reserved IP (`host/k3s-config.yaml`, Tailscale Connector, AdGuard notes)
   - ACME e-mail in `platform/cluster/cert-manager-issuers/letsencrypt.yaml`
5. **Discord alerts channel.** On your Discord server: create a private channel (e.g.
   `#homelab-alerts`) → Edit Channel → Integrations → Webhooks → *New Webhook* → copy the URL.
6. **Workstation tools:** `kubectl`, `kubeseal` (v0.40.x, to match the controller), `openssl`, [prek](https://github.com/j178/prek),
   and OpenTofu via [tenv](https://github.com/tofuutils/tenv) (`tenv tofu install` reads
   `.opentofu-version`), `helm`, `kubeconform`, [uv](https://docs.astral.sh/uv/) (runs `scripts/validate.py`
   with its own dependencies). Optional: `argocd` CLI, `k9s`.

---

## 6. Phase 1: Hardware and OS

**Hardware**
- Raspberry Pi 5 8 GB, **official 27 W (5.1 V / 5 A) USB-C PSU**. Weaker supplies cap USB current
  and cause brown-outs under load.
- **Active Cooler** (or a case with a fan). Throttling starts at 80 °C; the `PiHighTemperature`
  alert fires at 75 °C.
- An **M.2 HAT+ / NVMe base with an NVMe SSD** (a model known to work on the Pi, 500 GB-2 TB).
  If media lives on the same disk, size it for your library.
- **The 128 GB microSD card as the backup disk.** Once the Pi boots from NVMe, the card slot is free.
  A different device from the NVMe means one dead SSD doesn't take the backups with it.
  "High Endurance" cards cope best with nightly writes.

**OS: Raspberry Pi OS Lite (64-bit, Trixie)**
1. Flash with Raspberry Pi Imager directly to the NVMe drive (USB adapter), or to the SD card and then
   `rpi-clone` it to NVMe (the setup script wipes the card afterwards). In Imager set your user, an
   SSH key, Wi-Fi, and turn off password SSH. The hostname can be anything; step 3 renames it.
2. Boot from NVMe: `sudo rpi-eeprom-config --edit` and set `BOOT_ORDER=0xf416` (NVMe → SD → USB).
   Optional PCIe Gen 3 (faster, officially "not certified"): add `dtparam=pciex1_gen=3` to
   `/boot/firmware/config.txt`.
3. **Rename to `rpi-01` through cloud-init** (`host/set-hostname.sh`). Imager configures the hostname
   via cloud-init, which re-applies it from its *cache* on every boot, so a plain `hostnamectl`
   rename would be undone. The script edits cloud-init's seed (`/boot/firmware/user-data`) and drops
   only the cache; the instance ID stays, so no first-boot steps re-run. Do this **before** k3s: the
   node name is baked into certificates and volume node-affinities.
4. **Static address.** Reserve the Pi's IP (here `192.168.50.244`) in the router's DHCP. Keep the Pi's
   own resolver on the router or a public resolver, **not** AdGuard, or CoreDNS depends on a pod that
   isn't running yet at boot. **Ethernet** is recommended: over Wi-Fi, copies run at ~13 MB/s.
5. **Run the host setup** (`host/setup-pi.sh`, idempotent). It:
   - enables the **memory cgroup** in `cmdline.txt` (Pi firmware disables it; without it, memory
     limits are silently not enforced)
   - installs unattended-upgrades, parted, smartmontools, nvme-cli, jq; stages a newer bootloader
   - caps the journal at **1 GB / 1 month** (`host/journald-homelab.conf`)
   - turns **Wi-Fi power saving off** (latency spikes and dropped connections otherwise)
   - formats the **SD card as the backup disk** (ext4, label `backup`, mounted at `/srv/backup`) —
     only if it is `mmcblk0`, unmounted, 100–140 GB, and root is on NVMe. The empty mount point is
     made immutable, so if the card is ever missing, backups **fail** instead of silently filling
     the NVMe.
   - creates `/srv/backup/{restic,etcd}` and `/srv/media`

   ```bash
   scp host/setup-pi.sh host/set-hostname.sh host/journald-homelab.conf rpi:lichnovsky-setup/
   # sudo needs a real terminal: run these in your own terminal, not in a non-interactive shell
   ssh -t rpi 'sudo bash ~/lichnovsky-setup/set-hostname.sh rpi-01 && sudo reboot'
   ssh -t rpi 'sudo bash ~/lichnovsky-setup/setup-pi.sh 2>&1 | tee ~/lichnovsky-setup/setup.log && sudo reboot'
   # verify after the reboot: must print "memory"
   ssh rpi 'grep -o memory /sys/fs/cgroup/cgroup.controllers; findmnt /srv/backup; hostname'
   ```
6. **Swap.** Trixie ships a 2 GB zram swap; that's fine (k3s sets `failSwapOn: false`, pods don't
   swap). Don't add a swapfile on the SSD.
7. **Port 53 must be free** for AdGuard: `sudo ss -lunp | grep ':53 '` should print nothing.
8. **Media folder:** `sudo chown <you>: /srv/media`, so you can copy media there as your user
   (UID 1000, the same UID Jellyfin reads with).

Later, when you add a bigger backup disk, mount it at `/srv/backup` instead and copy the folder over
(`rsync -aH`). The cluster doesn't notice the difference.

---

## 7. Phase 2: k3s

```bash
# on the Pi (edit node-ip in host/k3s-config.yaml first)
sudo install -D -m 0600 host/k3s-config.yaml /etc/rancher/k3s/config.yaml
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION="v1.36.4+k3s1" sh -
```

Work from your laptop: copy the admin kubeconfig (root-only on the Pi, by design), point it at the
Pi, and give the context a real name:
```bash
ssh -t rpi 'mkdir -p ~/.kube && sudo install -m 0600 -o "$USER" /etc/rancher/k3s/k3s.yaml ~/.kube/config'
(umask 077; mkdir -p ~/.kube && ssh rpi 'cat ~/.kube/config' > ~/.kube/config)   # no -t: keeps LF line endings
sed -i 's#127.0.0.1#192.168.50.244#; s/\bdefault\b/lichnovsky/g' ~/.kube/config
kubectl get nodes -o wide     # rpi-01 Ready
```
The API certificate already covers the IP and `rpi-01`/`rpi-01.local` via `tls-san`. (On the Pi
itself, `kubectl` is k3s's wrapper, which reads the root-only file; use `sudo` there, or the laptop.)

Then cap k3s's Go heap (`host/k3s-memory.conf`, a systemd drop-in, so reinstalls don't touch it):
```bash
sudo install -D -m 0644 host/k3s-memory.conf /etc/systemd/system/k3s.service.d/memory.conf
sudo systemctl daemon-reload && sudo systemctl restart k3s   # pods keep running during the restart
```

What the config does, and why:

| Setting | Reason |
|---|---|
| `write-kubeconfig-mode: 0600` | The original guide's `644` made the cluster-admin credential readable by every local user |
| `cluster-init: true` | Embedded etcd instead of SQLite. Enables more servers later and `k3s etcd-snapshot` (every 12 h, keep 10) |
| Traefik and ServiceLB **kept** | ServiceLB publishes Traefik on the node IP, which LAN/Tailscale access needs. Disabling it (as the original guide did) leaves Traefik unreachable from the LAN |
| `system-reserved` / `kube-reserved` / `eviction-hard` | The kubelet evicts one pod before the kernel OOM-kills something important |
| `container-log-max-size/files` | Caps container logs on the SSD |
| No controller-manager/scheduler/etcd metrics | k3s runs them in one process; not worth the extra series on 8 GB |

---

## 8. Phase 3: Argo CD bootstrap and secrets

```bash
# 1. Install Argo CD with the same values it will later use to manage itself
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace --version 10.9.2 \
  -f bootstrap/argocd-values.yaml

# 2. Give Argo CD read access to the private repo with a read-only DEPLOY KEY.
#    (Repo-scoped, not tied to your account, no expiry. GitHub's host keys ship with Argo CD.)
ssh-keygen -t ed25519 -N '' -C argocd@lichnovsky.eu -f ~/.config/lichnovsky/argocd-deploy-key
#    GitHub -> JersyJ/lichnovsky -> Settings -> Deploy keys -> Add: paste the .pub, leave
#    "Allow write access" OFF. Keep the private key in your password manager as well.
kubectl -n argocd create secret generic repo-lichnovsky \
  --from-literal=type=git \
  --from-literal=url=git@github.com:JersyJ/lichnovsky.git \
  --from-file=sshPrivateKey=$HOME/.config/lichnovsky/argocd-deploy-key
kubectl -n argocd label secret repo-lichnovsky argocd.argoproj.io/secret-type=repository

# 3. Hand over to GitOps
kubectl apply -f bootstrap/root.yaml
```

Argo CD now installs **stage 1**. First come waves -10 and -9: itself, Sealed Secrets and
cert-manager. Wave -8 (`platform`) waits until its secrets exist. **That's expected.** The controller has to be running
before you can seal anything:

```bash
# 4. Seal the stage-1 secrets (prompts only for tokens you paste; generates the rest)
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
source ~/.config/lichnovsky/cloudflare.env   # for the tunnel token from `tofu output`
for s in cloudflare-api-token cloudflared-token grafana-admin papra backups; do scripts/seal.sh $s; done
# later stages, once you have the values: alertmanager-notify, tailscale-operator-oauth, vaultwarden
git add apps && git commit -m "feat: sealed secrets" && git push

# 5. Back up the Sealed Secrets private key OFF the cluster (password manager / offline).
#    Without it, a rebuilt cluster can't decrypt anything in Git.
(umask 077; kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > ~/sealed-secrets-key.backup.yaml)   # store it safely, then delete the local file

# 6. Also save the k3s server token: needed to restore the cluster from an etcd snapshot.
ssh -t rpi 'sudo cat /var/lib/rancher/k3s/server/token'
```

If the `argocd` app then hangs at *waiting for deletion of hook … argocd-redis-secret-init*: the
first `helm install` created that hook's objects, and Argo CD won't delete what it doesn't own.
Delete them once (§15); the `argocd-redis` Secret itself is kept.

`scripts/seal.sh <name>` asks only for values you have to paste: the cert-manager DNS token, the
Discord webhook URL, the Tailscale OAuth client, and the Vaultwarden `ADMIN_TOKEN`. That
last one is an **argon2 hash**, not a password; the cluster can compute it:
`kubectl run vw-hash --rm -it --restart=Never --image=vaultwarden/server:1.37.3 -- /vaultwarden hash`.
Everything else is generated. The Grafana password and the **restic password** are printed once, so
save them in your password manager right away. Run `scripts/seal.sh` without arguments for the list.
Plaintext never touches the disk: the Secret is built in memory and reaches `kubeseal` via stdin.
A SealedSecret is encrypted for one **namespace + name**; moving an app to another namespace means
re-sealing its secrets. (gitleaks is told to ignore `sealed-*.yaml`; their ciphertext looks like keys.)

When stage 1 is healthy, continue stage by stage (§4, *Staged rollout*).

Watch the rollout: `kubectl -n argocd get applications -w`. You can also open the UI, which is
reachable before the tunnel is up with `kubectl -n argocd port-forward svc/argocd-server 8080:80`.
Initial admin password:
`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
Change it, then delete that secret.

---

## 9. Phase 4: Cloudflare Tunnel and Access (as code)

Everything on the Cloudflare side is OpenTofu in **`cloudflare/`**, with its state encrypted
in an R2 bucket. That covers the tunnel, its public hostnames, the DNS records, Access, the rate
limit, the cache rule and the TLS settings. The one-time bootstrap (R2 bucket, two tokens, Zero Trust
team) and the commands are in [`cloudflare/README.md`](../cloudflare/README.md).
**Do this before Phase 3 step 4**, because `scripts/seal.sh cloudflared-token` reads the tunnel token from
`tofu output`.

What it sets up, and why:
- **DNSSEC** (`dnssec.tf`): Cloudflare signs the zone. The chain of trust needs the key entered once
  at the registrar: `tofu output dnssec_keydata` (for `.eu`, Porkbun's *keyData*: flags 257,
  protocol 3, algorithm 13, public key) and `tofu output dnssec_ds` (*dsData*). Leave *Max Sig
  Life* empty. Check: public resolvers answer `AD: true` for `lichnovsky.eu`.
- **Heartbeat Worker** (`heartbeat.tf`, `workers/heartbeat.js`): checks `lichnovsky.eu/healthz` every
  5 min from Cloudflare and posts 🔴/🟢 to Discord (§12).
- **Public hostnames** `lichnovsky.eu`, `www`, `vault`, `photos`, `papra`, `status`, `argocd`,
  `grafana` → `http://traefik.kube-system.svc.cluster.local:80`, each with a proxied CNAME to the
  tunnel. **No wildcard**, so `tv` (Jellyfin) and `dns` (AdGuard) never get a public record.
- **Access** (e-mail one-time PIN) on `argocd.`, `grafana.`, `papra.`, `status.`, and on
  `vault.lichnovsky.eu/admin` only. Protecting all of `vault.` would break the Bitwarden apps.
  A second, path-specific app **bypasses** Access for Uptime Kuma's public status page
  (`/status`, `/status-page`, `/api/status-page`, `/assets`, `/upload`, icons); more specific paths
  win, so the admin UI stays protected. The first time Access is used, Zero Trust must be enabled
  once in the dashboard (team name + Free plan).
  Nothing on `photos.`: the Immich apps and share links need direct access, so they rely on
  Immich's own login plus the rate limit.
- **Rate limit** (the Free plan has one rule, which can match on **path only**, counted per IP over
  10 s): URI path contains `/identity/connect/token` (Vaultwarden) or `/api/auth/login` (Immich),
  10 requests / 10 s → block for 10 s.
- **Cache rule** for `lichnovsky.eu` (except `/healthz`): the website is served from Cloudflare's
  edge according to its `Cache-Control` headers. Without such a header, Cloudflare caches a page
  for **2 hours**, so the site must send one (the placeholder uses `max-age=60`, and `no-store` for
  its live status data).
- **TLS:** Full (strict), Always Use HTTPS, TLS ≥ 1.2. Add HSTS later, once everything works.
- **Real client IPs:** cloudflared passes `X-Forwarded-For`/`CF-Connecting-IP`. Traefik trusts
  forwarded headers from the pod network (`10.42.0.0/16`, see
  `platform/cluster/traefik/helmchartconfig.yaml`), and Vaultwarden reads `CF-Connecting-IP`.

**Limits to know:**
- **100 MB per request** on the Free/Pro plans. Immich uploads bigger videos in chunks, but
  anything that fails remotely will work on the LAN or over Tailscale.
- **No video streaming through the tunnel.** Cloudflare's CDN Service-Specific Terms (this
  replaced the old self-serve §2.8 in 2023) don't allow serving video from your own origin
  through the CDN, and a Tunnel counts. That's why Jellyfin is private.

---

## 10. Phase 5: LAN and remote access

### AdGuard Home (LAN DNS + split horizon)
1. Open `http://192.168.50.244:3000` and run the wizard. Web UI: *all interfaces, port 3000*. DNS:
   *all interfaces, port 53*. Port 80/443 belong to Traefik. (A fresh AdGuard only serves the
   wizard on :3000; DNS starts after it, which is why its health checks probe :3000, not :53.)
2. **Filters → DNS rewrites:** `lichnovsky.eu` → `192.168.50.244` and `*.lichnovsky.eu` →
   `192.168.50.244`. Everything, the website included, now runs on the Pi, so a wildcard is
   simplest. If you later host a subdomain elsewhere, add a more specific rewrite (or an
   exception) for it.
3. **Upstreams:** DoH to e.g. `https://dns.quad9.net/dns-query` and
   `https://cloudflare-dns.com/dns-query`. Turn on *parallel requests* and the cache.
4. **Test first, then switch the house:** query AdGuard directly (e.g. `github.com`, a rewrite such
   as `tv.lichnovsky.eu`, and a blocked ad domain like `doubleclick.net` → `0.0.0.0`).
   **Router DHCP → DNS server:** `192.168.50.244` first. **Also hand out a second resolver** (e.g.
   9.9.9.9). On ASUS, set *Advertise router's IP in addition to user-specified DNS* to **No**. Don't
   point the router's own WAN DNS at the Pi (the Pi resolves through the router: a loop at boot). The Pi is a single point of failure: when it reboots or
   upgrades, the house keeps working without ad blocking. Clients may use the secondary at any
   time, so some ads can get through. Accept that trade-off, or run a second AdGuard on rpi-02 and
   keep the two in sync with [adguardhome-sync](https://github.com/bakito/adguardhome-sync).

### Tailscale (remote access at LAN speed)
1. After the operator syncs (stage 3), the tailnet shows `lichnovsky-k8s-operator` and
   `lichnovsky-lan`; the `192.168.50.244/32` route is approved automatically by `autoApprovers`.
2. Admin console → **DNS → Nameservers → Add nameserver → Custom** → `192.168.50.244`, enable
   **Restrict to domain** → `lichnovsky.eu` (split DNS). Only `*.lichnovsky.eu` lookups go to AdGuard.
3. **Clients:** phones accept routes automatically. **Linux ignores subnet routes by default:**
   `sudo tailscale set --accept-routes`.
4. **Test from a phone on mobile data** (Wi-Fi off): `https://dns.lichnovsky.eu` (the AdGuard UI) has
   no public record, so if it loads, remote access works end to end.
5. To give family access to Jellyfin without joining your whole tailnet, **share** the machine
   from the admin console.

---

## 11. Phase 6: First run of each app

**Vaultwarden** (namespace `vaultwarden`). Open `https://vault.lichnovsky.eu/admin` (Access, then the
admin password whose hash you sealed) → *Users → Invite* your e-mail. Without SMTP the invitation
isn't mailed; you can register directly with that address at `https://vault.lichnovsky.eu`.
`SIGNUPS_ALLOWED=false` blocks everyone else. Choose the **master password** there: it encrypts the
vault and **nobody can reset it**, so write it down offline. Then turn on 2FA and keep the recovery
code with it. Clients: Bitwarden extension/apps → *self-hosted* → `https://vault.lichnovsky.eu`.
The web vault needs HTTPS; plain `http://` is redirected by Traefik.
Snapshots: a CronJob runs `vaultwarden backup` (SQLite `VACUUM INTO`) at 02:30, keeping 7, and
k8up copies them to the backup disk at 03:30.

**Papra** (namespace `papra`). `https://papra.lichnovsky.eu`: create the first account (the first
user is the owner), then close registration: `AUTH_IS_REGISTRATION_ENABLED=false` in
`apps/papra/papra.yaml` (already set in this repo). Data (SQLite + files) lives under
`/app/app-data` on the PVC; an init step creates its `db/` and `documents/` folders, because the
volume mount hides the ones in the image.

**Immich** (future stage, `argocd/later/stage-5-immich/`). `https://photos.lichnovsky.eu`: the first
user becomes admin.
- The database is CNPG `immich-db` (Postgres 17 + VectorChord 1.1.1). `vchord` and `earthdistance`
  are created at bootstrap, so Immich never needs superuser. A CronJob `pg_dump`s it at 03:00
  (keeps 7) into the `immich-db-dumps` PVC, which k8up backs up.
- **Turn off Immich's built-in database backup:** Administration → Settings → Backup Settings →
  disable. It's on by default (02:00, keeps 14) and uses `pg_dumpall`, which needs a Postgres
  superuser. Here it would fail every night. The CronJob above replaces it.
- For the first bulk import: Administration → Jobs → lower concurrency (thumbnail 1-2, ML 1),
  import from the LAN, and let it run overnight.
- Mobile app: server URL `https://photos.lichnovsky.eu`. At home AdGuard resolves it locally;
  away from home it goes through Cloudflare, or Tailscale for big videos.

**Jellyfin** (namespace `tv`). `https://tv.lichnovsky.eu` (LAN/Tailscale only).
**The Pi 5 has no hardware video encoder**, and Jellyfin has deprecated V4L2 acceleration on the
Pi. Plan for direct play:
- Store media as H.264 or HEVC + AAC in MP4/MKV, which almost every client plays directly.
- Dashboard → Playback: leave hardware acceleration **off**, and set a generous
  *Internet streaming bitrate limit* so remote clients don't transcode just because of bitrate.
- Expect at most one 1080p CPU transcode. For more, run Jellyfin on an Intel N100/N150 mini-PC
  (QuickSync); this manifest moves over as-is.
- **Setup wizard:** admin user; keep *Allow remote connections* **on** (all traffic arrives via
  Traefik, so Jellyfin can't tell local from remote anyway; the real protection is that the
  hostname only exists on the LAN and tailnet); keep *automatic port mapping* **off**.
- **Libraries:** Movies → `/media/movies`, Shows → `/media/shows`, Music → `/media/music`. Turn on
  real-time monitoring and *Automatically add to collection*. Turn **off** *Save artwork into media
  folders* and *Save metadata as NFO* (the media is mounted read-only), and **off** chapter-image
  and trickplay extraction (they decode every video in full, hours of CPU per movie on a Pi).
  Leave *Prefer embedded titles over filenames* off; file names are more reliable.
- **Media layout:** `movies/Title (Year)/Title (Year).mkv` (+ `Title (Year).cs.srt`),
  `shows/Show (Year)/Season 01/Show S01E01.mkv`. Copy from the laptop with rsync, e.g.
  `rsync -ah --mkpath --info=progress2 file.mkv "rpi:/srv/media/movies/Title (Year)/Title (Year).mkv"`.
  Check codecs first with `ffprobe`: H.264/AAC plays directly everywhere; HEVC 10-bit plays
  directly in the Jellyfin **apps**, but many **browsers** can't, which forces a CPU transcode.

**Website** (namespace `web`). `https://lichnovsky.eu` shows a placeholder page with a **live
status widget** until the real site exists (`apps/website/website.yaml`), and `www.` redirects to the
apex. The widget reads the public status page `home` through nginx (`/status-data/…` is proxied
inside the cluster to Uptime Kuma: same origin, so no CORS, and `no-store`, so Cloudflare never
caches it). Build the site in its own
repository. To plug it in, the image only has to meet this contract:

| Requirement | Why |
|---|---|
| `linux/arm64` image (multi-arch is fine), pushed to e.g. `ghcr.io/<you>/lichnovsky-website:<version>` | Runs on the Pi. Build it in GitHub Actions with `docker buildx --platform linux/amd64,linux/arm64` |
| Non-root, works with a read-only root filesystem (write only to `/tmp`) | Namespace `web` enforces the `restricted` Pod Security profile |
| HTTP on port **8080**; `GET /healthz` returns 200 | Matches the Service and the probes |
| Static (HTML/CSS/JS) served by nginx/Caddy, or a small server (Astro/Next standalone, Go...) | Either works; static is lighter and caches perfectly at Cloudflare |
| Sends `Cache-Control` headers for assets (e.g. hashed files `max-age=31536000, immutable`) | Lets the Cloudflare Cache Rule do the heavy lifting |

Then in `website.yaml`: set the new `image:`, delete the `website-placeholder` ConfigMap and the
`content` volume/volumeMount, and push. To keep the status widget, copy the `/status-data/` location
from `website-nginx` into your site's server config. Renovate picks up new site versions if you tag releases
(or use Argo CD Image Updater to deploy every build automatically). If the site's repo or image
is private, add an `imagePullSecrets` entry backed by a SealedSecret.

**Uptime Kuma** (namespace `monitoring`). `UPTIME_KUMA_DB_TYPE=sqlite` skips 2.x's database wizard,
so the first screen creates the admin. **Do this right after deploying:** on the LAN, Access doesn't
apply, and whoever opens it first becomes admin. Add HTTP monitors for each app and a DNS monitor
for AdGuard, and a Discord notification. **Status Pages → New** with slug **`home`**: it's public at
`https://status.lichnovsky.eu/status/home` (and feeds the website widget). Only what you put on the
page is shown.

**Grafana.** Get the password with
`kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`
(in your own terminal), log in as `admin`, and change it under *Profile*. The *Homelab* folder holds
the Cloudflare Tunnel, Traefik, Argo CD, CloudNativePG and Logs dashboards; *Node Exporter / Nodes*
shows the Pi itself. Grafana 13 runs its plugins as separate processes, hence the 768 Mi limit.

---

## 12. Day-2 operations

### Updates
- **Apps and charts: Renovate.** Install the [Renovate GitHub App](https://github.com/apps/renovate)
  on the repo (only `lichnovsky`). `renovate.json` groups patch updates into one weekly PR, puts major updates behind
  approval on the dependency dashboard, and keeps Immich server and ML on the same version.
  Merge a PR and Argo CD rolls it out. Read the release notes for Immich, CNPG and Argo CD majors.
- **Postgres image:** update by hand. A Postgres major version needs CNPG's major-upgrade
  procedure. Check Immich's supported VectorChord range (currently `>= 0.3, < 2.0`) before bumping.
- **k3s:** once a quarter, or when a CVE affects it. Take an etcd snapshot, then re-run the
  installer with the new `INSTALL_K3S_VERSION`, one minor version at a time. First check that
  your pinned charts support the new Kubernetes version. With two or more nodes, use
  [system-upgrade-controller](https://docs.k3s.io/upgrades/automated) plans instead.
- **OS:** unattended-upgrades handles security updates; reboot for kernel updates when convenient.

### Alerting (Discord) and an external heartbeat
Alertmanager is configured in `argocd/10-kube-prometheus-stack.yaml`.
Its webhook URL comes from the SealedSecret `alertmanager-notify` and is read from a file, so it
never appears in Git.
1. **Alertmanager → Discord.** Every alert goes to your Discord channel, grouped per namespace and
   alert, with a repeat every 12 h while it keeps firing and a message when it resolves. The rules
   in `platform/monitoring` add Pi temperature, tunnel down and memory pressure alerts to the
   built-in node/pod/PVC/disk alerts.
2. **External heartbeat.** Anything on the Pi dies with the Pi, so this check runs on
   **Cloudflare**: a Worker (`cloudflare/heartbeat.tf`, code in `cloudflare/workers/heartbeat.js`)
   fetches `https://lichnovsky.eu/healthz` every 5 minutes, through Cloudflare like a visitor. After
   **2 failed checks in a row** (~10 min) it posts 🔴 to Discord, and 🟢 with the downtime when the
   site is back. It catches a dead Pi, a power or internet outage, and a broken tunnel. It doesn't
   catch a broken monitoring stack while the site still works; Grafana shows that. Free plan; on a
   healthy day it makes no KV writes at all. Tested end to end: with cloudflared scaled to 0 (pause
   auto-sync on `root` and `cloudflared` first, or Argo CD restores it within seconds), 🔴 arrived
   after two checks, 🟢 after restoring with `kubectl apply -f bootstrap/root.yaml`.
3. **Test it** after enabling stage 2:
   ```bash
   kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093 &
   curl -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' \
     -d '[{"labels":{"alertname":"TestAlert","severity":"warning","namespace":"test"}}]'
   ```
   The alert should appear in Discord within about 30 s. When sealing the webhook, `seal.sh` rejects
   anything that isn't a `https://discord.com/api/webhooks/…` URL (a pasted stray `V` once broke it). The config was checked with Alertmanager's
   own `amtool check-config` (v0.34.1, the version the chart ships).

### Disk health
The NVMe drive holds everything. Check `sudo smartctl -a /dev/nvme0n1` monthly
(`Percentage Used`, `Media and Data Integrity Errors`), or add `smartctl_exporter` and alert on it.
Keep an eye on `retentionSize` (20 GB, 30 days) for Prometheus and 30-day retention for Loki. They are the
biggest writers.

---

## 13. Backups and disaster recovery

**Design (no cloud costs for now):** apps write consistent snapshots into their own volumes.
Nightly, k8up runs restic in each namespace and sends encrypted, deduplicated snapshots to a small
restic **rest-server** in the `backups` namespace. Each namespace has its own login there and can
only reach its own repository (`--private-repos`). It stores them on the **SD card**
(`/srv/backup`), a separate device from the NVMe.

```
Vaultwarden ── vaultwarden backup (02:30) ──┐
Immich DB ──── pg_dump (03:00) ─────────────┤
Papra, Uptime Kuma, AdGuard ───────────────┼──► k8up/restic (03:30-04:10) ──► rest-server ──► SD card /srv/backup/restic/<ns>
                                            │
k3s etcd snapshots (every 12 h) ────────────┴─────────────────────────────────────────────────► SD card /srv/backup/etcd
```

| What | How | Where | Schedule / retention |
|---|---|---|---|
| Git: manifests, config, sealed secrets | GitHub | GitHub (+ your laptop clone) | every push |
| Sealed Secrets **private key** | manual export (Phase 3 step 5) | password manager + offline | once, and after key rotation (every 30 days by default; old keys are kept) |
| Secret values + **restic password** | printed once by `scripts/seal.sh` → password manager | password manager | when created |
| Vaultwarden | SQLite `VACUUM INTO` snapshot → restic | SD card | daily; 7 d / 4 w / 6 m |
| Immich database (future stage) | `pg_dump -Fc` → restic | SD card | daily; 7 d / 4 w / 6 m |
| Papra, Uptime Kuma, AdGuard | restic (k8up) | SD card | daily; 7 d / 4 w / 6 m; weekly `restic check` |
| etcd (cluster state) | k3s `etcd-snapshot-schedule-cron` | SD card `/srv/backup/etcd` | every 12 h, keep 10 |
| k3s server token (needed to restore etcd) | manual (Phase 3 step 6) | password manager | once |
| **Not backed up (yet)** | **Immich photo library**; also Prometheus/Loki data, ML model cache, Jellyfin config, media library | - | Too big for 128 GB, or rebuildable |

**Will 128 GB be enough?** Yes, now that the photo library is left out. Vaultwarden, AdGuard,
Uptime Kuma and the Immich database dumps are megabytes, and Papra is usually a few GB. The
built-in `NodeFilesystemSpaceFillingUp` alerts fire long before the card is full.

**Details that matter:** the restic pods run as **root** (the k8up image's own UID 65532 can't read
files the apps write with mode 0600, e.g. Vaultwarden's `rsa_key.pem` or AdGuard's config, and would
silently skip them). Each namespace logs in to the rest-server with its own user
(`--private-repos`). k8up records the repository URL, including that login, in its `Snapshot`
objects; the login only reaches that namespace's (encrypted) repository.

**First restore test (done):** Vaultwarden's snapshot was restored into a separate volume. The
database copy was byte-identical to the live one, SQLite's integrity check said `ok`, and the
0600 `rsa_key.pem` was there too.

> ⚠️ **The Immich photo library has no backup yet.** The NVMe is its only copy in the homelab.
> Until the bigger backup disk exists:
> - **Keep the originals on your phones/cameras** (or in your old cloud). Don't use Immich's
>   *Free up space* / "delete from device after upload".
> - Now and then, copy the originals off the Pi (they're plain files):
>   `sudo rsync -a --exclude thumbs --exclude encoded-video /var/lib/rancher/k3s/storage/*_photos_immich-library/ /media/usb/immich/`
>   (originals are in `upload/`, or in `library/` if you turn on Immich's storage template)
>
> **When the bigger disk arrives:** mount it at `/srv/backup` (Phase 1, host setup), then add the
> annotation `k8up.io/backup: "true"` to the `immich-library` PVC in `apps/immich/immich.yaml`.
> The next nightly run backs up the library. Size the disk at *library size + 20 %* for history,
> or leave out `thumbs/` and `encoded-video/`, which Immich can regenerate.

**Be honest about what this protects against:**

| Failure | Protected? |
|---|---|
| Accidental deletion, a bad upgrade, ransomware inside an app, corrupted database | ✅ restore last night's snapshot |
| NVMe SSD dies | ✅ data is on the SD card |
| SD card dies | ✅ primary data unaffected; replace the card and back up again |
| Theft, fire, power surge (the whole Pi at once) | ❌ both copies are in the same box |

So until there's an off-site copy, **copy `/srv/backup` to your laptop or a USB disk now and then**.
It's encrypted, so it's safe to keep anywhere:
`rsync -aH --delete rpi-01:/srv/backup/ /path/to/usb/lichnovsky-backup/`
Later, adding off-site is one change: a second k8up Schedule, or `restic copy`, to R2/B2 or a
friend's rest-server.

### Restore drills
**An untested backup is a guess.** Run one of these every quarter.

- **Browse and get single files (any namespace):** from any machine with restic, while connected
  to the LAN/Tailscale:
  ```bash
  kubectl -n backups port-forward svc/rest-server 8000:8000 &
  # REST_PASSWORD for the namespace: kubectl -n papra get secret k8up-repo -o jsonpath='{.data.REST_PASSWORD}' | base64 -d
  export RESTIC_REPOSITORY=rest:http://papra:<REST_PASSWORD>@localhost:8000/papra/
  export RESTIC_PASSWORD=<restic password>
  restic snapshots
  restic restore latest --target ./restore --include /data/papra-data
  ```
- **Restore a whole volume (k8up):** restore into a *new* PVC, inspect it, then swap:
  ```yaml
  apiVersion: k8up.io/v1
  kind: Restore
  metadata: { name: restore-papra, namespace: papra }
  spec:
    restoreMethod:
      folder: { claimName: papra-restore }
    podSecurityContext: { runAsUser: 0 }
    backend:
      repoPasswordSecretRef: { name: k8up-repo, key: RESTIC_PASSWORD }
      rest:
        url: http://rest-server.backups.svc.cluster.local:8000/papra
        userSecretRef: { name: k8up-repo, key: REST_USER }
        passwordSecretReg: { name: k8up-repo, key: REST_PASSWORD }
  ```
- **Immich database:** CNPG recreates an empty `immich-db` with the extensions, then:
  ```bash
  kubectl -n photos scale deploy/immich-server --replicas=0
  kubectl -n photos cp ./immich-YYYYMMDD-HHMMSS.dump immich-db-1:/var/lib/postgresql/data/restore.dump
  kubectl -n photos exec -it immich-db-1 -- pg_restore --clean --if-exists --no-owner \
    --role=immich -d immich /var/lib/postgresql/data/restore.dump
  kubectl -n photos scale deploy/immich-server --replicas=1
  ```
- **Vaultwarden:** stop the pod, copy the chosen `db_<timestamp>.sqlite3` over `db.sqlite3` in the
  restored volume (delete `db.sqlite3-wal`/`-shm`), start it again.
- **Whole NVMe lost:** new SSD → Phases 1-2 (the host setup leaves a card labelled `backup` alone; it only mounts it) →
  `kubectl apply` the saved Sealed Secrets key **before** installing Argo CD → Phase 3 steps 1-3 →
  Argo CD rebuilds everything → restore volumes and the DB as above. With this page open, expect
  about 2 hours plus restore time.

---

## 14. Adding a second Raspberry Pi

1. Phase 1 on the new board (hostname `rpi-02`, reserved IP, cgroups, journald).
2. Join as an **agent** (a worker; one etcd member is fine and two would be *worse* than one):
   ```bash
   # on rpi-01
   sudo cat /var/lib/rancher/k3s/server/node-token
   # on rpi-02
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.4+k3s1" \
     K3S_URL=https://192.168.50.244:6443 K3S_TOKEN=<token> sh -s - agent --node-name rpi-02
   ```
3. What moves where:
   - **Stays on rpi-01:** anything with a `local-path` PVC. local-path volumes are tied to their
     node, so these pods can't move: Postgres, Vaultwarden, Papra, Immich server, Prometheus, Loki,
     and the backup rest-server (the SD card is in rpi-01).
     AdGuard is pinned because clients use rpi-01's IP.
   - **Goes to rpi-02:** Immich ML (uncomment the affinity in `apps/immich/immich.yaml`), the
     second cloudflared replica (the spread constraint does this automatically), CI runners, and
     stateless experiments. The website can run one replica on each node.
   - Better backups: rpi-02 can hold a **second copy** of `/srv/backup` (e.g. a nightly
     `rsync`/`restic copy` to its own disk). That's still one house, but two boxes.
   - Optional: a second AdGuard on rpi-02 as the secondary DNS, kept in sync with adguardhome-sync.
4. **HA control plane needs three servers** (etcd quorum). Two nodes give more capacity, not
   more availability. Replicated storage (Longhorn) only makes sense at three nodes with fast
   networking. On Pis it costs more RAM and SSD wear than it saves.

---

## 15. Known pitfalls

| Symptom | Cause / fix |
|---|---|
| `argocd` app stuck: *waiting for deletion of hook … argocd-redis-secret-init* | The first `helm install` created that hook's Job/SA/Role/RoleBinding, and Argo CD won't delete objects it doesn't own. Delete them once: `kubectl -n argocd delete job,rolebinding,role,serviceaccount argocd-redis-secret-init`. The existing `argocd-redis` Secret is kept, and the next syncs are fine. |
| `platform` app stuck *Progressing* after bootstrap | Its SealedSecrets aren't committed yet. Run Phase 3 step 4. |
| cloudflared pod *Running* but sites return 1033/530 | The liveness probe on `/ready` (200 only while ≥ 1 edge connection is up) restarts it. If it keeps happening, check outbound UDP 7844 (QUIC). Some ISPs/routers block it; add `--protocol http2` to the args. |
| Pods OOM-killed while memory limits "look fine" | The memory cgroup isn't enabled. `grep memory /sys/fs/cgroup/cgroup.controllers` must match (Phase 1 step 4). |
| AdGuard restarts every ~80 s right after deploy | A fresh AdGuard only runs its wizard on :3000; DNS on :53 starts after the wizard. Probes must check :3000 (fixed in this repo). |
| Vaultwarden: "You are not using a secure context … Subtle Crypto API" | The page was opened over `http://`. Traefik now redirects to HTTPS; type `https://` if it ever happens again. |
| Grafana restarts, kernel log shows `gpx_grafana-*` killed | Grafana 13's plugin processes exceeded the memory limit. The limit is 768 Mi now. |
| Discord alerts fail: `unsupported protocol scheme "vhttps"` | A stray character was pasted into the hidden prompt. Re-seal; `seal.sh` now validates the URL. |
| gitleaks blocks a commit on `sealed-*.yaml` | Ciphertext looks like secrets. `.gitleaks.toml` exempts only `sealed-*.yaml`; if you rename one, keep the prefix. |
| An app is reachable at home without the Access login | By design: Access only covers the internet path. Each app needs its own login and closed sign-ups (§3). |
| A file's changes don't show on `lichnovsky.eu` | Cloudflare's edge cache (2 h without a `Cache-Control` header). Send the header, or purge the cache in the dashboard. |
| AdGuard CrashLoop: `bind: address already in use` | Something else on the host holds :53 (`ss -lunp`), or the wizard set the web UI to port 80, which Traefik owns. |
| Certificate stuck `Issuing` | Cloudflare token scope must be *Zone:DNS:Edit* on `lichnovsky.eu`. cert-manager checks propagation via 1.1.1.1/9.9.9.9 on purpose, so AdGuard rewrites don't confuse it. |
| Immich server restarts during first start | DB migrations: the startupProbe allows 5 min. Check `kubectl -n photos logs deploy/immich-server`. |
| Bitwarden app: "cannot connect" only when away from home | Cloudflare Access is on the whole `vault.` host instead of just `/admin`. |
| k8up backups fail with "connection refused" / rest-server pod `Pending` | The SD card isn't mounted (`findmnt /srv/backup`). The local PV path doesn't exist, so the pod can't start, which is intended. Reseat the card and run `sudo mount /srv/backup`. |
| Large upload fails remotely, works at home | The 100 MB Cloudflare request limit. Use Tailscale. |
| Prometheus eats the disk | `retentionSize: 20GB` caps it. Lower `retention` if the SSD is small. |

---

## 16. References

- k3s requirements (cgroups on Raspberry Pi OS): https://docs.k3s.io/installation/requirements
- k3s HelmChartConfig: https://docs.k3s.io/helm
- Raspberry Pi firmware disabling the memory cgroup: https://homelabpostmortem.com/2026/08/19/pi-memory-cgroup-disabled-by-firmware/
- Argo CD sync waves and Application health: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/
- Sealed Secrets: https://github.com/bitnami/sealed-secrets
- Promtail EOL → Alloy: https://grafana.com/docs/alloy/latest/set-up/migrate/from-promtail/
- Loki Helm (single binary): https://grafana.com/docs/loki/latest/setup/install/helm/
- CNPG Barman Cloud plugin, for when an S3/R2 bucket is added: https://cloudnative-pg.io/plugin-barman-cloud/docs/migration/
- restic rest-server: https://github.com/restic/rest-server
- Immich requirements and Postgres/VectorChord: https://docs.immich.app/install/requirements/ · https://docs.immich.app/administration/postgres-standalone/
- Immich environment variables and metrics: https://docs.immich.app/install/environment-variables/ · https://docs.immich.app/features/monitoring/
- Jellyfin hardware acceleration (Pi 5 has no encoder): https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/
- Cloudflare ToS change (§2.8 → CDN terms): https://blog.cloudflare.com/updated-tos/
- Vaultwarden WebSockets on the main port since 1.29: https://github.com/dani-garcia/vaultwarden/discussions/3671
- Papra configuration / Docker: https://docs.papra.app/self-hosting/configuration/ · https://docs.papra.app/self-hosting/using-docker/
- Tailscale Kubernetes operator: https://tailscale.com/kb/1236/kubernetes-operator
- Cloudflare provider for OpenTofu/Terraform: https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs
- OpenTofu state encryption: https://opentofu.org/docs/language/state/encryption/
- Rate limiting via API / Cache Rules via API (token permissions): https://developers.cloudflare.com/waf/rate-limiting-rules/create-api/ · https://developers.cloudflare.com/cache/how-to/cache-rules/create-api/
- k8up: https://docs.k8up.io/
- Renovate Argo CD manager: https://docs.renovatebot.com/modules/manager/argocd/
