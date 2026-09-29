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
9. [Phase 4: Cloudflare Tunnel and Access](#9-phase-4-cloudflare-tunnel-and-access)
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
| Photos | **Immich** | Google Photos replacement | v3.2.2 |
| Postgres | **CloudNativePG** + VectorChord image | Declarative Postgres; nightly `pg_dump` for backups | chart 0.29.1 / 1.30.1 |
| Media | **Jellyfin** (LAN/Tailscale, direct play) | Open source. The Pi 5 has **no HW encoder**, see §11 | 12.1 |
| Metrics | **kube-prometheus-stack** | Prometheus Operator, Grafana, Alertmanager, node-exporter, KSM | 91.8.1 |
| Logs | **Loki** (single binary) + **Grafana Alloy** | Alloy replaces Promtail, which reached EOL on 2026-03-02 | 7.3.0 / 1.13.0 |
| Uptime | **Uptime Kuma** 2.x | Friendly checks + status page | 2.5.5 |
| Backups | **k8up** (restic) → **restic rest-server** on the SD card | Encrypted, deduplicated nightly snapshots on a second device; no cloud bill | 4.10.0 / 0.14.0 |
| Website | **nginx-unprivileged** placeholder, to be replaced by your own image | Served from the Pi through the tunnel | 1.31.6 |
| Updates | **Renovate** | Opens PRs for new chart/image versions; you merge, Argo CD deploys | - |

### Honest memory budget (8 GB Pi)

The numbers are typical steady-state working sets. Limits in the manifests are higher, so a single
pod can burst.

| Group | Typical RAM |
|---|---|
| OS, containerd, k3s server with embedded etcd | 700 - 900 MB |
| k3s add-ons (Traefik, CoreDNS, metrics-server, local-path, svclb) | ~150 MB |
| Argo CD (controller, repo-server, server, redis, appset) | 400 - 550 MB |
| Operators (Sealed Secrets, cert-manager, CNPG, k8up + rest-server, Tailscale + connector) | ~300 MB |
| kube-prometheus-stack (Prometheus, Grafana, operator, KSM, node-exporter, Alertmanager) | 700 - 1,000 MB |
| Loki + Alloy | 250 - 350 MB |
| cloudflared ×2, AdGuard, Vaultwarden, Papra, Uptime Kuma, website (placeholder) | ~450 MB |
| Immich server + Postgres + Valkey (ML idle) | 700 - 1,100 MB |
| Jellyfin (idle / direct play) | 200 - 400 MB |
| **Idle total** | **≈ 3.9 - 5.2 GB** |
| Immich ML while indexing (face/CLIP models loaded) | +1.0 - 1.5 GB |
| Immich thumbnail / video transcode jobs, Jellyfin CPU transcode | +0.5 - 1.0 GB |
| **Busy peak** | **≈ 6 - 7.5 GB** |

What this means:
- The idle total fits comfortably. **The first big photo import will not** fit comfortably. For the
  initial upload, lower Immich's job concurrency (Administration → Jobs) and let it run overnight.
- The kubelet reserves 768 Mi and evicts pods below 256 Mi free (`host/k3s-config.yaml`), so a busy
  moment kills one pod instead of freezing the whole Pi.
- If RAM is tight, move **Immich ML** to the second Pi first; it's the biggest variable load.
  Turning ML off (Administration → Settings → Machine Learning) also works.

---

## 3. Hostnames and exposure

| Hostname | App | Public (tunnel) | Cloudflare Access | LAN / Tailscale |
|---|---|---|---|---|
| `lichnovsky.eu` | Website | yes | no | yes |
| `www.lichnovsky.eu` | 301 → `lichnovsky.eu` | yes | no | yes |
| `vault.lichnovsky.eu` | Vaultwarden | yes | only on `/admin` | yes |
| `photos.lichnovsky.eu` | Immich | yes | no (breaks mobile app + share links) | yes |
| `papra.lichnovsky.eu` | Papra | yes | yes (email OTP / GitHub) | yes |
| `status.lichnovsky.eu` | Uptime Kuma | yes | yes, with bypass for `/status/*` if you want a public status page | yes |
| `argocd.lichnovsky.eu` | Argo CD | yes | **yes, required** | yes |
| `grafana.lichnovsky.eu` | Grafana | yes | **yes, required** | yes |
| `tv.lichnovsky.eu` | Jellyfin | **no** | - | yes |
| `dns.lichnovsky.eu` | AdGuard UI | **no** | - | yes |

Private names never get a public DNS record. They only exist as AdGuard rewrites, and Tailscale
reaches them through split DNS.

---

## 4. Repository layout, sync order and staged rollout

```
lichnovsky/                    # github.com/JersyJ/lichnovsky
├── bootstrap/
│   ├── argocd-values.yaml     # Argo CD Helm values (used by bootstrap AND by Argo CD itself)
│   └── root.yaml              # the only thing you kubectl-apply: syncs argocd/
├── argocd/                    # ENABLED Applications (stage 1); sync-wave sets the order
│   └── later/stage-2…5/       # not deployed yet: move files up into argocd/ one stage at a time
├── apps/
│   ├── platform/              # namespaces (PSA), Traefik config, TLS, ClusterIssuer, infra secrets
│   ├── tailscale/             # Connector (subnet router)
│   ├── networking/            # cloudflared, AdGuard
│   ├── security/vaultwarden/
│   ├── documents/papra/
│   ├── photos/immich/         # Immich + CNPG cluster + nightly pg_dump CronJob
│   ├── media/jellyfin/
│   ├── monitoring/            # uptime-kuma, monitors (ServiceMonitors, alert rules)
│   ├── web/website/           # lichnovsky.eu (placeholder until the real site exists)
│   └── backups/               # restic rest-server on the SD card + k8up Schedules
├── cloudflare/                # OpenTofu: tunnel, DNS, Access, rules, zone settings (state in R2)
├── host/                      # files that go on the Pi itself (k3s config, journald cap)
├── scripts/
│   ├── seal.sh                # create one SealedSecret; plaintext never touches the disk
│   ├── validate.py            # helm-render every chart + kubeconform + stage check, offline
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
| **5 Heavy apps** | CloudNativePG + Immich, then Jellyfin | first Immich import overnight at low job concurrency; watch memory before adding Jellyfin |

Enabling a stage: `git mv argocd/later/stage-2-observability/*.yaml argocd/ && git commit -m "feat: stage 2" && git push`.
Nothing in an early stage depends on a CRD from a later one (for example, cloudflared's
ServiceMonitor lives with the stage-2 monitors), and `scripts/validate.py` enforces that.

### Checks and git hooks
- **`scripts/validate.py`** renders every chart (all stages) with its pinned version and values,
  validates the ~400 resources, CRDs included, with kubeconform, and runs the **stage check**:
  any custom resource in an *enabled* app must have its CRD installed by an enabled chart or by k3s.
  It needs `helm` and `kubeconform` on `PATH`.
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

1. **Domain on Cloudflare.** `lichnovsky.eu` uses Cloudflare nameservers (Free plan is fine).
   - SSL/TLS → Edge Certificates: turn on *Always Use HTTPS*, and *HSTS* once everything works.
2. **Cloudflare API token for cert-manager** (manual on purpose): My Profile → API Tokens →
   template *Edit zone DNS*, zone `lichnovsky.eu` only. The OpenTofu bootstrap (R2 bucket,
   OpenTofu token, Zero Trust team) is in `cloudflare/README.md`; see Phase 4.
3. **Tailscale account.** In the tailnet policy, add `tagOwners` for `tag:k8s-operator` and `tag:k8s`.
   Then create the operator's OAuth client
   ([KB 1236](https://tailscale.com/kb/1236/kubernetes-operator) lists the current scopes).
4. **Private GitHub repo** `JersyJ/lichnovsky`. Push this folder to it, then replace every
   `CHANGEME` (`grep -rn CHANGEME .`):
   - `git@github.com:JersyJ/lichnovsky.git` → your repo URL (in `bootstrap/root.yaml` and `argocd/*.yaml`):
     `grep -rl 'github.com/JersyJ/' . | xargs sed -i 's#github.com/JersyJ/#github.com/<your-user>/#'`
   - `192.168.50.244` → the Pi's reserved IP (`host/k3s-config.yaml`, Tailscale Connector, AdGuard notes)
   - ACME e-mail in `apps/platform/cert-manager-issuers/letsencrypt.yaml`
5. **Discord alerts channel.** On your Discord server: create a private channel (e.g.
   `#homelab-alerts`) → Edit Channel → Integrations → Webhooks → *New Webhook* → copy the URL.
6. **Workstation tools:** `kubectl`, `kubeseal` (v0.40.x, to match the controller), `openssl`, [prek](https://github.com/j178/prek),
   and OpenTofu via [tenv](https://github.com/tofuutils/tenv) (`tenv tofu install` reads
   `.opentofu-version`), `helm`, `kubeconform`. Optional: `argocd` CLI, `k9s`.

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
   `rpi-clone` it to NVMe (step 9 wipes the card afterwards). Set hostname `rpi-01`, your user, an SSH key, and turn off password SSH.
2. Boot from NVMe: `sudo rpi-eeprom-config --edit` and set `BOOT_ORDER=0xf416` (NVMe → SD → USB).
   Optional PCIe Gen 3 (faster, officially "not certified"): add `dtparam=pciex1_gen=3` to
   `/boot/firmware/config.txt`.
3. **Update the OS and firmware:** `sudo apt update && sudo apt full-upgrade -y && sudo rpi-eeprom-update -a`.
4. **Enable the memory cgroup.** It is required: Pi firmware still adds `cgroup_disable=memory` on its
   own. Without this, memory limits are silently not enforced, which makes the RAM plan above useless.
   ```bash
   sudo sed -i '1 s/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/firmware/cmdline.txt
   sudo reboot
   # verify: must print "memory"
   grep -o memory /sys/fs/cgroup/cgroup.controllers
   ```
5. **Static address.** Reserve `192.168.50.244` for the Pi in the router's DHCP. Keep the Pi's own
   resolver on the router or a public resolver, **not** AdGuard, or CoreDNS depends on a pod
   that isn't running yet at boot.
6. **Cap the journal** and turn on security updates:
   ```bash
   sudo install -D -m 0644 host/journald-homelab.conf /etc/systemd/journald.conf.d/homelab.conf
   sudo systemctl restart systemd-journald
   sudo apt install -y unattended-upgrades && sudo dpkg-reconfigure -plow unattended-upgrades
   ```
7. **Swap.** Check `swapon --show`. A small zram swap is fine as a last resort. Don't add a swapfile
   on the SSD.
8. **Port 53 must be free** for AdGuard: `sudo ss -lunp | grep ':53 '` should print nothing.
9. **Backup disk: the SD card at `/srv/backup`.** Check with `lsblk` that the card is `mmcblk0` and
   that you booted from NVMe (`findmnt /` shows `nvme0n1p2`). **This erases the card.**
   ```bash
   sudo wipefs -a /dev/mmcblk0
   sudo parted -s /dev/mmcblk0 mklabel gpt mkpart backup ext4 0% 100%
   sudo mkfs.ext4 -L backup /dev/mmcblk0p1

   # Make the empty mount point immutable. If the card is ever missing, backups then FAIL
   # instead of silently filling the NVMe underneath.
   sudo mkdir -p /srv/backup && sudo chattr +i /srv/backup
   echo 'LABEL=backup /srv/backup ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2' \
     | sudo tee -a /etc/fstab
   sudo systemctl daemon-reload && sudo mount /srv/backup

   sudo mkdir -p /srv/backup/restic /srv/backup/etcd
   sudo chown 1000:1000 /srv/backup/restic      # the rest-server pod runs as UID 1000
   sudo mkdir -p /srv/media                     # Jellyfin library (on the NVMe)
   ```
   Later, when you add a bigger disk, mount it at `/srv/backup` instead and copy the folder over
   (`rsync -aH`). The cluster doesn't notice the difference.

---

## 7. Phase 2: k3s

```bash
sudo mkdir -p /etc/rancher/k3s
sudo cp host/k3s-config.yaml /etc/rancher/k3s/config.yaml    # edit node-ip first!
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.4+k3s1" sh -

# kubeconfig for your user (the file is root-only by design)
mkdir -p ~/.kube && sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/config && chmod 600 ~/.kube/config
kubectl get nodes -o wide     # rpi-01 Ready
```

From your laptop: copy the same file and replace `127.0.0.1` with `192.168.50.244`.
The API cert already covers it via `tls-san`.

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
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-key.backup.yaml     # git-ignored; store it safely, then delete it locally
```

`scripts/seal.sh <name>` asks only for values you have to paste: the cert-manager DNS token, the
Discord webhook URL, the Tailscale OAuth client, and the Vaultwarden `ADMIN_TOKEN`. That
last one is an **argon2 hash**, not a password: `docker run --rm -it vaultwarden/server:1.37.3 /vaultwarden hash`.
Everything else is generated. The Grafana password and the **restic password** are printed once, so
save them in your password manager right away. Run `scripts/seal.sh` without arguments for the list.

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
- **Public hostnames** `lichnovsky.eu`, `www`, `vault`, `photos`, `papra`, `status`, `argocd`,
  `grafana` → `http://traefik.kube-system.svc.cluster.local:80`, each with a proxied CNAME to the
  tunnel. **No wildcard**, so `tv` (Jellyfin) and `dns` (AdGuard) never get a public record.
- **Access** (e-mail one-time PIN) on `argocd.`, `grafana.`, `papra.`, `status.`, and on
  `vault.lichnovsky.eu/admin` only. Protecting all of `vault.` would break the Bitwarden apps.
  Nothing on `photos.`: the Immich apps and share links need direct access, so they rely on
  Immich's own login plus the rate limit.
- **Rate limit** (the Free plan has one rule, which can match on **path only**, counted per IP over
  10 s): URI path contains `/identity/connect/token` (Vaultwarden) or `/api/auth/login` (Immich),
  10 requests / 10 s → block for 10 s.
- **Cache rule** for `lichnovsky.eu`: the website is served from Cloudflare's edge according to
  its `Cache-Control` headers, so traffic spikes and short Pi restarts barely matter.
- **TLS:** Full (strict), Always Use HTTPS, TLS ≥ 1.2. Add HSTS later, once everything works.
- **Real client IPs:** cloudflared passes `X-Forwarded-For`/`CF-Connecting-IP`. Traefik trusts
  forwarded headers from the pod network (`10.42.0.0/16`, see
  `apps/platform/traefik/helmchartconfig.yaml`), and Vaultwarden reads `CF-Connecting-IP`.

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
   *all interfaces, port 53*. Port 80/443 belong to Traefik.
2. **Filters → DNS rewrites:** `lichnovsky.eu` → `192.168.50.244` and `*.lichnovsky.eu` →
   `192.168.50.244`. Everything, the website included, now runs on the Pi, so a wildcard is
   simplest. If you later host a subdomain elsewhere, add a more specific rewrite (or an
   exception) for it.
3. **Upstreams:** DoH to e.g. `https://dns.quad9.net/dns-query` and
   `https://cloudflare-dns.com/dns-query`. Turn on *parallel requests* and the cache.
4. **Router DHCP → DNS server:** `192.168.50.244` first. **Also hand out a second resolver** (e.g.
   the router itself or 9.9.9.9). The Pi is a single point of failure: when it reboots or
   upgrades, the house keeps working without ad blocking. Clients may use the secondary at any
   time, so some ads can get through. Accept that trade-off, or run a second AdGuard on rpi-02 and
   keep the two in sync with [adguardhome-sync](https://github.com/bakito/adguardhome-sync).

### Tailscale (remote access at LAN speed)
1. After the operator syncs, approve the `192.168.50.244/32` route of `lichnovsky-lan` in the
   Tailscale admin console (or add an `autoApprovers` rule).
2. **DNS → Nameservers → Add → Custom → `192.168.50.244`, "Restrict to domain" `lichnovsky.eu`**
   (split DNS). Now a phone on Tailscale resolves `tv.lichnovsky.eu` to the Pi and reaches it
   over the tailnet, with the same URL and certificate as at home.
3. For Jellyfin/Immich away from home, keep Tailscale on (or on-demand) on the phone.

---

## 11. Phase 6: First run of each app

**Vaultwarden.** Open `https://vault.lichnovsky.eu/admin` (Access, then the admin password whose
hash you sealed). Configure SMTP (needed for invitations and 2FA recovery), invite yourself, then
sign up via the invite. `SIGNUPS_ALLOWED=false` blocks everyone else. Turn on 2FA in the account.
Snapshots: a CronJob runs `vaultwarden backup` (SQLite `VACUUM INTO`) at 02:30, keeping 7, and
k8up copies them to the backup disk at 03:30.

**Papra.** `https://papra.lichnovsky.eu`: create the first account (the first user is the owner).
Data (SQLite + files) lives under `/app/app-data` on the PVC.

**Immich.** `https://photos.lichnovsky.eu`: the first user becomes admin.
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

**Jellyfin.** `https://tv.lichnovsky.eu` (LAN/Tailscale).
**The Pi 5 has no hardware video encoder**, and Jellyfin has deprecated V4L2 acceleration on the
Pi. Plan for direct play:
- Store media as H.264 or HEVC + AAC in MP4/MKV, which almost every client plays directly.
- Dashboard → Playback: leave hardware acceleration **off**, and set a generous
  *Internet streaming bitrate limit* so remote clients don't transcode just because of bitrate.
- Expect at most one 1080p CPU transcode. For more, run Jellyfin on an Intel N100/N150 mini-PC
  (QuickSync); this manifest moves over as-is.
- Media: put files in `/srv/media` on the Pi. The container sees it read-only at `/media`.

**Website.** `https://lichnovsky.eu` shows a placeholder page until the real site exists
(`apps/web/website/website.yaml`), and `www.` redirects to the apex. Build the site in its own
repository. To plug it in, the image only has to meet this contract:

| Requirement | Why |
|---|---|
| `linux/arm64` image (multi-arch is fine), pushed to e.g. `ghcr.io/<you>/lichnovsky-website:<version>` | Runs on the Pi. Build it in GitHub Actions with `docker buildx --platform linux/amd64,linux/arm64` |
| Non-root, works with a read-only root filesystem (write only to `/tmp`) | Namespace `web` enforces the `restricted` Pod Security profile |
| HTTP on port **8080**; `GET /healthz` returns 200 | Matches the Service and the probes |
| Static (HTML/CSS/JS) served by nginx/Caddy, or a small server (Astro/Next standalone, Go...) | Either works; static is lighter and caches perfectly at Cloudflare |
| Sends `Cache-Control` headers for assets (e.g. hashed files `max-age=31536000, immutable`) | Lets the Cloudflare Cache Rule do the heavy lifting |

Then in `website.yaml`: set the new `image:`, delete the `website-placeholder` ConfigMap and the
`content` volume/volumeMount, and push. Renovate picks up new site versions if you tag releases
(or use Argo CD Image Updater to deploy every build automatically). If the site's repo or image
is private, add an `imagePullSecrets` entry backed by a SealedSecret.

**AdGuard, Uptime Kuma, Grafana.** Uptime Kuma: `UPTIME_KUMA_DB_TYPE=sqlite` skips 2.x's
database wizard, so the first screen asks you to create the admin account. Add HTTP monitors for
each public URL and a DNS monitor for AdGuard. Grafana: log in with the sealed `grafana-admin` credentials. The
*Homelab* folder holds the Cloudflare Tunnel, Traefik, Argo CD, CloudNativePG and Logs dashboards.

---

## 12. Day-2 operations

### Updates
- **Apps and charts: Renovate.** Install the [Renovate GitHub App](https://github.com/apps/renovate)
  on the repo. `renovate.json` groups patch updates into one weekly PR, puts major updates behind
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
Alertmanager is configured in `argocd/later/stage-2-observability/10-kube-prometheus-stack.yaml`.
Its webhook URL comes from the SealedSecret `alertmanager-notify` and is read from a file, so it
never appears in Git.
1. **Alertmanager → Discord.** Every alert goes to your Discord channel, grouped per namespace and
   alert, with a repeat every 12 h while it keeps firing and a message when it resolves. The rules
   in `apps/monitoring/monitors` add Pi temperature, tunnel down and memory pressure alerts to the
   built-in node/pod/PVC/disk alerts.
2. **External heartbeat.** Anything on the Pi dies with the Pi, so this check runs on
   **Cloudflare**: a Worker (`cloudflare/heartbeat.tf`, code in `cloudflare/workers/heartbeat.js`)
   fetches `https://lichnovsky.eu/healthz` every 5 minutes, through Cloudflare like a visitor. After
   **2 failed checks in a row** (~10 min) it posts 🔴 to Discord, and 🟢 with the downtime when the
   site is back. It catches a dead Pi, a power or internet outage, and a broken tunnel. It doesn't
   catch a broken monitoring stack while the site still works; Grafana shows that. Free plan; on a
   healthy day it makes no KV writes at all.
3. **Test it** after enabling stage 2:
   ```bash
   kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093 &
   curl -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' \
     -d '[{"labels":{"alertname":"TestAlert","severity":"warning","namespace":"test"}}]'
   ```
   The alert should appear in Discord within about 30 s. The config was checked with Alertmanager's
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
| Immich database | `pg_dump -Fc` → restic | SD card | daily; 7 d / 4 w / 6 m |
| Papra, Uptime Kuma, AdGuard | restic (k8up) | SD card | daily; 7 d / 4 w / 6 m; weekly `restic check` |
| etcd (cluster state) | k3s `etcd-snapshot-schedule-cron` | SD card `/srv/backup/etcd` | every 12 h, keep 10 |
| **Not backed up (yet)** | **Immich photo library**; also Prometheus/Loki data, ML model cache, Jellyfin config, media library | - | Too big for 128 GB, or rebuildable |

**Will 128 GB be enough?** Yes, now that the photo library is left out. Vaultwarden, AdGuard,
Uptime Kuma and the Immich database dumps are megabytes, and Papra is usually a few GB. The
built-in `NodeFilesystemSpaceFillingUp` alerts fire long before the card is full.

> ⚠️ **The Immich photo library has no backup yet.** The NVMe is its only copy in the homelab.
> Until the bigger backup disk exists:
> - **Keep the originals on your phones/cameras** (or in your old cloud). Don't use Immich's
>   *Free up space* / "delete from device after upload".
> - Now and then, copy the originals off the Pi (they're plain files):
>   `sudo rsync -a --exclude thumbs --exclude encoded-video /var/lib/rancher/k3s/storage/*_photos_immich-library/ /media/usb/immich/`
>   (originals are in `upload/`, or in `library/` if you turn on Immich's storage template)
>
> **When the bigger disk arrives:** mount it at `/srv/backup` (Phase 1 step 9), then add the
> annotation `k8up.io/backup: "true"` to the `immich-library` PVC in `apps/photos/immich/immich.yaml`.
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
  # REST_PASSWORD for the namespace: kubectl -n documents get secret k8up-repo -o jsonpath='{.data.REST_PASSWORD}' | base64 -d
  export RESTIC_REPOSITORY=rest:http://documents:<REST_PASSWORD>@localhost:8000/documents/
  export RESTIC_PASSWORD=<restic password>
  restic snapshots
  restic restore latest --target ./restore --include /data/papra-data
  ```
- **Restore a whole volume (k8up):** restore into a *new* PVC, inspect it, then swap:
  ```yaml
  apiVersion: k8up.io/v1
  kind: Restore
  metadata: { name: restore-papra, namespace: documents }
  spec:
    restoreMethod:
      folder: { claimName: papra-restore }
    podSecurityContext: { runAsUser: 0 }
    backend:
      repoPasswordSecretRef: { name: k8up-repo, key: RESTIC_PASSWORD }
      rest:
        url: http://rest-server.backups.svc.cluster.local:8000/documents
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
- **Whole NVMe lost:** new SSD → Phases 1-2 (**don't** wipe the SD card in step 9; just mount it) →
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
   - **Goes to rpi-02:** Immich ML (uncomment the affinity in `apps/photos/immich/immich.yaml`), the
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
| `platform` app stuck *Progressing* after bootstrap | Its SealedSecrets aren't committed yet. Run Phase 3 step 4. |
| cloudflared pod *Running* but sites return 1033/530 | The liveness probe on `/ready` (200 only while ≥ 1 edge connection is up) restarts it. If it keeps happening, check outbound UDP 7844 (QUIC). Some ISPs/routers block it; add `--protocol http2` to the args. |
| Pods OOM-killed while memory limits "look fine" | The memory cgroup isn't enabled. `grep memory /sys/fs/cgroup/cgroup.controllers` must match (Phase 1 step 4). |
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
