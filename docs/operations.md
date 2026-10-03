# Operations

Day-to-day work once everything runs: changing things, updates, alerts, backups and restores, and
fixes for known problems.

## Changing things

Edit, commit, push; Argo CD applies it within ~3 minutes. Anything changed with `kubectl edit` is
reverted by self-heal. The pre-push hook runs `scripts/validate.py` (renders every chart, validates
all manifests, checks the sync order).

- **New secret:** a case in `scripts/seal.sh`. Keep the `sealed-` file-name prefix (gitleaks ignores
  only those).
- **New app:** a folder in `apps/` plus an Application in `argocd/`.
- **Website:** edit `web/` and push; CI builds and deploys it ([web/README.md](../web/README.md)).
- **Media stack settings** (quality profiles, naming, download client, Prowlarr's app links): edit
  `apps/media/configarr.yaml` and push. Configarr applies it at :17 every hour, or right away with
  `kubectl -n tv create job --from=cronjob/configarr configarr-now`.

## Updates

- **Charts and images:** Renovate (`.github/renovate.json`) opens PRs on Saturdays: patch updates
  grouped into one PR, majors only after approval on its dependency dashboard. Merge and Argo CD rolls
  it out. Read the release notes for majors.
- **k3s:** once a quarter, or for a CVE. Bump `K3S_VERSION` in `host/03-install-k3s.sh`, copy it to
  the Pi and run it again: it takes an etcd snapshot, then upgrades. One minor version at a time, and
  check that the pinned charts support the new Kubernetes version first.
- **OS:** unattended-upgrades installs security updates; reboot for kernel updates when convenient.

## Alerts

- **Alertmanager → Discord.** Alerts are grouped per namespace and alert name, repeat every 12 h while
  firing, and send a message when resolved. `platform/monitoring/monitors.yaml` adds Pi temperature,
  tunnel down and memory pressure to the built-in node/pod/disk alerts. Test:
  ```bash
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093 &
  curl -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' \
    -d '[{"labels":{"alertname":"TestAlert","severity":"warning","namespace":"test"}}]'
  ```
- **Argo CD → Discord** (same channel): ❌ when a sync fails, with Argo CD's error, and ✅ when an
  app finished syncing a new revision and is healthy (chart version or commit). Configured under
  `notifications` in `bootstrap/argocd-values.yaml`.
- **Heartbeat Worker.** Anything on the Pi dies with the Pi, so a Cloudflare Worker fetches
  `https://lichnovsky.eu/healthz` every 5 minutes. After 2 failures in a row it posts 🔴 to Discord,
  and 🟢 with the downtime when the site is back. It catches a dead Pi, power or internet outages and a
  broken tunnel. To test it, pause auto-sync on `root` and `cloudflared` (otherwise Argo CD undoes it
  within seconds), scale cloudflared to 0, wait ~10 min, then `kubectl apply -f bootstrap/root.yaml`.
- **Disk health:** `sudo smartctl -a /dev/nvme0n1` monthly (*Percentage Used*, *Media and Data
  Integrity Errors*). Prometheus (20 GB / 30 days) and Loki (30 days) are the biggest writers.

## Backups

Apps write consistent snapshots into their own volumes. Nightly, k8up runs restic in each namespace
and sends encrypted, deduplicated snapshots to the restic rest-server, which stores them on the
SD card. Each namespace has its own repository and login and can reach only its own (`--private-repos`).

```
Vaultwarden ── vaultwarden backup (02:30) ──┐
Immich DB ──── pg_dump (03:00) ─────────────┤
Papra, Uptime Kuma, AdGuard ────────────────┼──► k8up/restic (03:30-04:10) ──► rest-server ──► /srv/backup/restic/<ns>
k3s etcd snapshots (every 12 h) ────────────┴─────────────────────────────────────────────────► /srv/backup/etcd
```

| What | Where | When / retention |
|---|---|---|
| Manifests, config, sealed secrets | GitHub | every push |
| Sealed Secrets private key | password manager + offline | after setup, and now and then (rotates every 30 days) |
| restic password, Grafana password, k3s token | password manager | when created |
| Vaultwarden, Papra, Uptime Kuma, AdGuard, media stack settings (Sonarr, Radarr, Prowlarr, Bazarr, Seerr, qBittorrent) | SD card | daily; 7 daily / 4 weekly / 6 monthly; weekly `restic check` |
| etcd (cluster state) | SD card | every 12 h, keep 10 |
| **Not backed up:** Prometheus/Loki data, Jellyfin config and media (incl. downloads), Immich photo library | – | rebuildable, or too big for the card |

**Lose the restic password and the backups are unreadable.**

**Backing up another namespace:** `scripts/seal.sh backup-namespace <ns>` adds a login for it
(keeping the others), then add a Schedule in `platform/backups/schedules.yaml` and the namespace to
the NetworkPolicy in `platform/backups/rest-server.yaml`. Backups are opt-in: only PVCs annotated
`k8up.io/backup: "true"` are included. A schedule that finds none still reports *Succeeded* ("nothing
to backup"), so check for a fresh snapshot after adding one.

The restic pods run as root: the k8up image's own UID can't read files apps write with mode 0600
(e.g. Vaultwarden's `rsa_key.pem`) and would silently skip them. If the SD card is missing, the
empty `/srv/backup` mount point is immutable, so backups fail loudly instead of filling the NVMe.

**What this protects against:** deleted data, bad upgrades, corruption, a dead NVMe, a dead SD card.
**Not** theft, fire or a power surge: both copies are in the same box. Until there is an off-site
copy, copy the (encrypted) backups to a laptop or USB disk now and then:
`rsync -aH --delete rpi-01:/srv/backup/ /path/to/usb/lichnovsky-backup/`.
For a bigger backup disk: mount it at `/srv/backup` instead of the card and `rsync -aH` the folder
over; nothing in the cluster changes.

### Restore

Test one restore a quarter; an untested backup is a guess.

- **Single files, any namespace:**
  ```bash
  kubectl -n backups port-forward svc/rest-server 8000:8000 &
  # REST_PASSWORD: kubectl -n papra get secret k8up-repo -o jsonpath='{.data.REST_PASSWORD}' | base64 -d
  export RESTIC_REPOSITORY=rest:http://papra:<REST_PASSWORD>@localhost:8000/papra/
  export RESTIC_PASSWORD=<restic password>
  restic snapshots
  restic restore latest --target ./restore --include /data/papra-data
  ```
- **Whole volume:** restore into a *new* PVC with k8up, inspect it, then swap:
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
- **Vaultwarden:** stop the pod, copy the chosen `db_<timestamp>.sqlite3` over `db.sqlite3` in the
  restored volume (delete `db.sqlite3-wal`/`-shm`), start it again.
- **Whole NVMe lost:** new SSD → [setup.md](setup.md) steps 3–6, restoring the Sealed Secrets key
  before handing over to Git (the host script leaves a card labelled `backup` alone) → Argo CD
  rebuilds everything → restore the volumes as above. About 2 hours plus restore time.

## Enabling Immich

Immich (with CloudNativePG for Postgres) is ready in `argocd/later/immich/` but not deployed. It
runs **without machine learning**, for RAM ([architecture.md → Memory](architecture.md#memory)). Without ML
there is no smart search ("dog on a beach"), no faces/people, no duplicate detection and no OCR;
backup from the phones, timeline, albums, sharing, the map and search by date/place/camera work.

1. `git mv argocd/later/immich/*.yaml argocd/ && git commit -m "feat: enable Immich" && git push`
2. `https://photos.lichnovsky.eu`: the first user becomes admin.
3. **Administration → Settings → Machine Learning → disable**: there is no ML container, so ML jobs
   would only fail.
4. **Administration → Settings → Backup Settings → disable** Immich's own database backup: it uses
   `pg_dumpall`, which needs a Postgres superuser, and fails every night here. A CronJob `pg_dump`s
   the database at 03:00 instead, and k8up backs that up.
5. First import: Administration → Jobs → thumbnail concurrency 1–2, import on the LAN, and let it run
   overnight.

**ML later, without using the Pi's RAM:** run the `immich-machine-learning` container (same version
as the server) with Docker on a laptop or desktop, and add its URL under Administration → Machine
Learning. Jobs get processed while that machine is online; otherwise they fail and are re-run with
*Missing* on the Job Status page. It has no authentication and receives image previews, so only over
the LAN or Tailscale.

**The photo library itself is not backed up** (too big for the SD card). Keep the originals on the
phones and don't use *Free up space*. With a bigger backup disk, add
`k8up.io/backup: "true"` to the `immich-library` PVC.

Restoring the Immich database from a dump:
```bash
kubectl -n photos scale deploy/immich-server --replicas=0
kubectl -n photos cp ./immich-YYYYMMDD-HHMMSS.dump immich-db-1:/var/lib/postgresql/data/restore.dump
kubectl -n photos exec -it immich-db-1 -- pg_restore --clean --if-exists --no-owner \
  --role=immich -d immich /var/lib/postgresql/data/restore.dump
kubectl -n photos scale deploy/immich-server --replicas=1
```
The Postgres image isn't updated by Renovate: a major version needs CNPG's upgrade procedure, and
the VectorChord version must stay in Immich's supported range.

## Media stack

```
Seerr ──request──► Radarr / Sonarr ──search──► Prowlarr ──► indexers (FlareSolverr if tagged)
                        │ ▲
                  grab  │ │ import (hardlink, rename)          Bazarr: subtitles next to the video
                        ▼ │
                    qBittorrent ──► /media/downloads   ──►   /media/movies, /media/shows ──► Jellyfin
```

Everything mounts the media volume at `/media`, so paths are the same in every app and an import is
a hardlink: a finished download is in the library at once and keeps seeding without taking space
twice. qBittorrent stops seeding at ratio 1 or after 24 h, then Sonarr/Radarr remove the torrent;
the library copy stays.

### Adding a movie or show

Family members use Seerr: [movies-and-shows.md](movies-and-shows.md) is their guide. Requests from
users with *Auto-Approve* (Seerr → *Users*) and your own start at once; the rest wait under
*Requests* for approval, and Discord tells you. Issues people report arrive the same way.

Behind a request, Radarr/Sonarr search every indexer and take the best release the quality profile
allows (TRaSH: good 1080p WEB/Bluray groups first, no fakes, re-encodes or low quality). qBittorrent
downloads it, the import renames and hardlinks it into the library, Jellyfin shows it, Bazarr adds
subtitles within the hour, and Discord reports the import. If nothing acceptable exists yet, the
title stays wanted: new releases are checked every ~15 minutes and it is grabbed as soon as one fits.
A better release later replaces the file (an upgrade).

**Directly in Radarr or Sonarr** (more options):
- Radarr → *Movies → Add New* → search → root folder `/media/movies`, profile *HD Bluray + WEB*,
  monitor *Movie Only*, minimum availability *Released*, tick *Start search for missing movie* →
  *Add Movie*.
- Sonarr → *Series → Add New* → root folder `/media/shows`, profile *WEB-1080p*, monitor *All
  Episodes* (*Future Episodes* for only what airs from now on), series type *Standard* (*Anime* or
  *Daily* for those), season folders on, tick *Start search for missing episodes* → *Add*.

**Picking the release yourself:** on a movie, season or episode, **Interactive Search** (the person
icon) lists every release found, with the reason a rejected one doesn't fit; the download icon grabs
one. For a specific cut, or when the automatic search finds nothing acceptable.

**Language:** the profiles accept the original language only (an English film in English); dubbed
releases are rejected, and Bazarr supplies Czech and English subtitles. To allow dubbing, change the
language settings in `apps/media/configarr.yaml`.

**Files you already have:** copy them in with the naming from [setup.md](setup.md) (Jellyfin), then
Radarr → *Movies → Library Import* (or Sonarr → *Series → Library Import*), so they get upgrades and
subtitles too: Bazarr only works on titles that Sonarr/Radarr know.

**Missing episodes of a show you already have:** Seerr requests whole seasons only, and a season
Jellyfin has even partly can't be requested there. Import the show in Sonarr (*Library Import*,
monitor *Last Season* or *Missing Episodes*, tick *Start search for missing episodes*); Sonarr keeps
the existing files and fetches the rest. Then Seerr → *Settings → Jobs & Cache* → *Sonarr Scan* →
*Run Now* updates Seerr.

**Removing:** in Radarr/Sonarr → the title → *Delete*, with *Delete files* ticked. Deleting only in
Jellyfin or on disk makes a still-monitored title download again. In Seerr, *Manage → Clear Data*
on the title lets it be requested again.

### When something is stuck

- **Indexers** are added by hand in Prowlarr (not in Git: this repository is public); Prowlarr
  pushes them to Sonarr and Radarr.
- **Nothing downloads:** Sonarr/Radarr → *Activity → Queue* shows why; *System → Status* lists
  broken indexers or a failing download client. Prowlarr → *Indexers* → test each. A failed
  download is blocklisted and another release is searched automatically.
- **An indexer is missing in Radarr or Sonarr:** they refuse an indexer whose test search returns
  nothing in their categories (movies 2000s, TV 5000s); Prowlarr's log shows `400` for that app. Use
  an indexer that carries that kind of content.
- **Import fails with "hardlink"/"permission":** all pods run as UID 1000 and `/srv/media` must
  belong to it (`sudo chown -R 1000:1000 /srv/media` on the Pi).
- **Settings drift back:** that's Configarr; change `apps/media/configarr.yaml` instead.

**VPN later:** qBittorrent has no VPN now; it connects from the home IP. To add one, take a provider
with port forwarding (e.g. ProtonVPN, AirVPN), put a [Gluetun](https://github.com/qdm12/gluetun)
sidecar into the qBittorrent pod with the provider's WireGuard key (a new `seal.sh` case), and drop
the `qbittorrent-bt` LoadBalancer and the router forward. All of qBittorrent's traffic then goes
through the tunnel, and Gluetun's firewall blocks it while the VPN is down.

## Adding a second Pi

1. [setup.md](setup.md) step 3 up to the host scripts `01` and `02` on the new board, as `rpi-02`.
   Without an SD card, `02-setup-pi.sh` stops at the backup-disk step; everything before it is done.
2. Join it as an **agent** (one etcd member is fine; two would be *worse* than one):
   ```bash
   ssh -t rpi 'sudo cat /var/lib/rancher/k3s/server/node-token'
   # on rpi-02
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.4+k3s1" \
     K3S_URL=https://192.168.50.244:6443 K3S_TOKEN=<token> sh -s - agent --node-name rpi-02
   ```
3. Anything with a `local-path` volume stays on rpi-01 (volumes are tied to their node), and AdGuard
   is pinned there. The second cloudflared replica, Immich machine learning and stateless
   workloads can move.
   rpi-02 can also hold a second copy of `/srv/backup`, or a second AdGuard kept in sync with
   [adguardhome-sync](https://github.com/bakito/adguardhome-sync).

A highly available control plane needs three servers; two nodes add capacity, not availability.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `argocd` app stuck: *waiting for deletion of hook … argocd-redis-secret-init* | The bootstrap `helm install` created these objects and Argo CD won't delete what it doesn't own: `kubectl -n argocd delete job,rolebinding,role,serviceaccount argocd-redis-secret-init` |
| `platform` app stuck *Progressing* after bootstrap | Its SealedSecrets can't be decrypted yet ([setup.md, step 6](setup.md#6-argo-cd-and-secrets)) |
| cloudflared *Running* but sites return 1033/530 | No edge connection. Outbound UDP 7844 (QUIC) may be blocked; add `--protocol http2` to its args |
| Pods OOM-killed although limits look fine | Memory cgroup not enabled: `grep memory /sys/fs/cgroup/cgroup.controllers` |
| AdGuard CrashLoop: `bind: address already in use` | Something on the host holds :53 (`ss -lunp`), or the web UI was set to port 80, which Traefik owns |
| Vaultwarden: "not a secure context … Subtle Crypto API" | Opened over `http://`; use `https://` |
| Grafana restarts, kernel log shows `gpx_grafana-*` killed | Its plugin processes exceeded the memory limit; raise it in `argocd/10-kube-prometheus-stack.yaml` |
| Discord alerts fail: `unsupported protocol scheme` | A stray character in the pasted webhook URL; re-run `scripts/seal.sh alertmanager-notify` |
| Changes don't show on `lichnovsky.eu` | Cloudflare's edge cache; send `Cache-Control`, or purge in the dashboard |
| Certificate stuck `Issuing` | The cert-manager token needs *Zone:DNS:Edit* on `lichnovsky.eu` |
| Bitwarden app "cannot connect" only away from home | Access is on the whole `vault.` host instead of just `/admin` |
| Backups fail, rest-server pod `Pending` | SD card not mounted (`findmnt /srv/backup`); reseat it and `sudo mount /srv/backup` |
| Large upload fails remotely, works at home | Cloudflare's 100 MB request limit; use Tailscale |
