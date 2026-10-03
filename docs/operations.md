# Operations

This document is for the daily work after the installation: changes, updates, alerts, backups,
restores, and solutions for known problems.

## Change the configuration

1. Edit the files.
2. Commit and push.

Argo CD applies the change in approximately 3 minutes. If you change a resource with
`kubectl edit`, self-heal reverts the change. The pre-push hook runs `scripts/validate.py`. The
script renders all charts, validates all manifests and checks the sync order.

- **New secret:** Add a case in `scripts/seal.sh`. Start the file name with `sealed-`, because
  gitleaks ignores only these files.
- **New app:** Add a folder in `apps/` and an Application in `argocd/`.
- **Website:** Edit `web/` and push. CI builds and deploys the website. Refer to
  [web/README.md](../web/README.md).
- **Media stack settings** (quality profiles, naming, download client, app links of Prowlarr): Edit
  `apps/media/configarr.yaml` and push. Configarr applies the settings at :17 each hour. To apply
  them immediately, run `kubectl -n tv create job --from=cronjob/configarr configarr-now`.

## Updates

- **Charts and images:** Renovate (`.github/renovate.json`) makes pull requests on Saturdays. It
  puts all patch updates into one pull request. For a major update, you must first approve it on
  the dependency dashboard. When you merge a pull request, Argo CD deploys it. For major updates,
  read the release notes.
- **k3s:** Update k3s one time each quarter, or for a CVE.
  1. Make sure that the pinned charts support the new Kubernetes version.
  2. Change `K3S_VERSION` in `host/03-install-k3s.sh`.
  3. Copy the script to the Pi and run it again. The script makes an etcd snapshot and then
     upgrades k3s.

  Upgrade only one minor version at a time.
- **Operating system:** unattended-upgrades installs the security updates. For kernel updates,
  restart the Pi at a time that is convenient.

## Alerts

- **Alertmanager → Discord.** Alertmanager groups the alerts by namespace and alert name. It sends
  an active alert again each 12 hours, and it sends a message when the problem is solved.
  `platform/monitoring/monitors.yaml` adds alerts for the Pi temperature, the tunnel and the memory
  pressure. To test Alertmanager:
  ```bash
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093 &
  curl -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' \
    -d '[{"labels":{"alertname":"TestAlert","severity":"warning","namespace":"test"}}]'
  ```
- **Argo CD → Discord** (same channel). Argo CD sends ❌ with its error when a sync fails. It sends
  ✅ when an app is healthy with a new revision (chart version or commit). The configuration is
  under `notifications` in `bootstrap/argocd-values.yaml`.
- **Heartbeat Worker.** If the Pi stops, all monitors on the Pi stop too. Thus, a Cloudflare Worker
  gets `https://lichnovsky.eu/healthz` each 5 minutes. After 2 failures in sequence, it sends 🔴 to
  Discord. When the site is available again, it sends 🟢 with the downtime. The Worker finds a
  stopped Pi, a power or internet failure and a broken tunnel. To test the Worker:
  1. Stop auto-sync on `root` and `cloudflared`. If you do not, Argo CD reverts the next step.
  2. Scale cloudflared to 0.
  3. Wait approximately 10 minutes.
  4. Run `kubectl apply -f bootstrap/root.yaml`.
- **Disk health:** Each month, run `sudo smartctl -a /dev/nvme0n1`. Look at *Percentage Used* and
  *Media and Data Integrity Errors*. Prometheus (20 GB / 30 days) and Loki (30 days) write the most
  data.

## Backups

The apps write consistent snapshots into their own volumes. Each night, k8up runs restic in each
namespace. restic sends encrypted, deduplicated snapshots to the restic rest-server, which keeps them
on the SD card. Each namespace has its own repository and login, and can get only to its own
repository (`--private-repos`).

```
Vaultwarden ── vaultwarden backup (02:30) ──┐
Immich DB ──── pg_dump (03:00) ─────────────┤
Papra, Uptime Kuma, AdGuard, media stack ───┼──► k8up/restic (03:30-04:20) ──► rest-server ──► /srv/backup/restic/<ns>
k3s etcd snapshots (each 12 h) ─────────────┴─────────────────────────────────────────────────► /srv/backup/etcd
```

| Data | Location | Frequency / retention |
|---|---|---|
| Manifests, configuration, sealed secrets | GitHub | Each push |
| Private key of Sealed Secrets | Password manager and offline | After the installation, and again from time to time (the key changes each 30 days) |
| restic password, Grafana password, k3s token | Password manager | When you make them |
| Vaultwarden, Papra, Uptime Kuma, AdGuard, media stack settings (Sonarr, Radarr, Prowlarr, Bazarr, Seerr, qBittorrent) | SD card | Each day. Keep 7 daily, 4 weekly, 6 monthly. `restic check` each week. |
| etcd (cluster state) | SD card | Each 12 hours. Keep 10. |
| **No backup:** Prometheus and Loki data, Jellyfin configuration and media (also the downloads), Immich photo library | – | You can make them again, or they are too large for the card |

**If you lose the restic password, you cannot read the backups.**

**To back up a different namespace:**

1. Run `scripts/seal.sh backup-namespace <ns>`. This adds a login for the namespace and keeps the
   other logins.
2. Add a Schedule in `platform/backups/schedules.yaml`.
3. Add the namespace to the NetworkPolicy in `platform/backups/rest-server.yaml`.
4. Add the annotation `k8up.io/backup: "true"` to each PVC that you want in the backup.
5. After the next backup, make sure that a new snapshot exists.

k8up backs up only PVCs with this annotation. If a schedule finds no PVC, it still shows
*Succeeded* ("nothing to backup").

The restic pods run as root. The UID of the k8up image cannot read files with mode 0600 (for
example `rsa_key.pem` of Vaultwarden). Without root, restic skips these files and shows no error.
If the SD card is not installed, the empty mount point `/srv/backup` is immutable. Thus, the
backups fail with an error and do not fill the NVMe.

**The backups protect against:** deleted data, bad upgrades, corruption, a broken NVMe, a broken SD
card. **They do not protect against** theft, fire or a power surge, because the two copies are in
the same box. Until you have an off-site copy, copy the encrypted backups to a laptop or USB disk
from time to time:

```bash
rsync -aH --delete rpi-01:/srv/backup/ /path/to/usb/lichnovsky-backup/
```

For a larger backup disk, mount the disk at `/srv/backup` instead of the card. Then copy the folder
with `rsync -aH`. You do not have to change the cluster.

### Restore

Do a restore test each quarter. If you do not test a backup, you do not know that it works.

- **Single files, all namespaces:**
  ```bash
  kubectl -n backups port-forward svc/rest-server 8000:8000 &
  # REST_PASSWORD: kubectl -n papra get secret k8up-repo -o jsonpath='{.data.REST_PASSWORD}' | base64 -d
  export RESTIC_REPOSITORY=rest:http://papra:<REST_PASSWORD>@localhost:8000/papra/
  export RESTIC_PASSWORD=<restic password>
  restic snapshots
  restic restore latest --target ./restore --include /data/papra-data
  ```
- **Full volume:** Restore into a *new* PVC with k8up. Examine the data, then replace the old PVC.
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
- **Vaultwarden:**
  1. Stop the pod.
  2. In the restored volume, copy the applicable `db_<timestamp>.sqlite3` over `db.sqlite3`.
  3. Delete `db.sqlite3-wal` and `db.sqlite3-shm`.
  4. Start the pod again.
- **Loss of the full NVMe:**
  1. Install a new SSD.
  2. Do [setup.md](setup.md) steps 3–6. Restore the Sealed Secrets key before you give control to
     Git. The host script does not change a card with the label `backup`.
  3. Argo CD builds all apps again.
  4. Restore the volumes as described above.

  This takes approximately 2 hours, plus the restore time.

## Enable Immich

Immich (with CloudNativePG for Postgres) is ready in `argocd/later/immich/`, but it is not deployed.
Immich operates **without machine learning**, because of the RAM (refer to
[architecture.md → Memory](architecture.md#memory)).

- **Not available without machine learning:** smart search ("dog on a beach"), faces and persons,
  duplicate detection, OCR.
- **Available:** backup from the phones, timeline, albums, sharing, the map, and search by date,
  location and camera.

1. Run `git mv argocd/later/immich/*.yaml argocd/ && git commit -m "feat: enable Immich" && git push`.
2. Open `https://photos.lichnovsky.eu`. The first user becomes the admin.
3. Disable machine learning: **Administration → Settings → Machine Learning**. There is no
   machine-learning container, thus the jobs can only fail.
4. Disable the database backup of Immich: **Administration → Settings → Backup Settings**. This
   backup uses `pg_dumpall`, which needs a Postgres superuser. Thus, it fails each night. Instead, a
   CronJob runs `pg_dump` at 03:00, and k8up backs up the dump.
5. For the first import, set the thumbnail concurrency to 1–2 (**Administration → Jobs**). Import
   on the LAN, and let the import run during the night.

**Machine learning later, without the RAM of the Pi:** Run the `immich-machine-learning` container
with Docker on a laptop or desktop. Use the same version as the server. Add its URL under
**Administration → Machine Learning**. The jobs run while that computer is on. Other jobs fail. To
run them again, use *Missing* on the Job Status page. The container has no authentication and gets
image previews. Thus, use it only on the LAN or through Tailscale.

**The photo library has no backup**, because it is too large for the SD card. Keep the originals on
the phones, and do not use *Free up space*. With a larger backup disk, add
`k8up.io/backup: "true"` to the PVC `immich-library`.

To restore the Immich database from a dump:

```bash
kubectl -n photos scale deploy/immich-server --replicas=0
kubectl -n photos cp ./immich-YYYYMMDD-HHMMSS.dump immich-db-1:/var/lib/postgresql/data/restore.dump
kubectl -n photos exec -it immich-db-1 -- pg_restore --clean --if-exists --no-owner \
  --role=immich -d immich /var/lib/postgresql/data/restore.dump
kubectl -n photos scale deploy/immich-server --replicas=1
```

Renovate does not update the Postgres image. A major version needs the upgrade procedure of CNPG.
The VectorChord version must also stay in the range that Immich supports.

## Media stack

```
Seerr ──request──► Radarr / Sonarr ──search──► Prowlarr ──► indexers (FlareSolverr if tagged)
                        │ ▲
                  grab  │ │ import (hardlink, rename)          Bazarr: subtitles next to the video
                        ▼ │
                    qBittorrent ──► /media/downloads   ──►   /media/movies, /media/shows ──► Jellyfin
```

All apps mount the media volume at `/media`. Thus, the paths are the same in all apps, and an
import is a hardlink. A completed download is in the library immediately. It continues to seed and
does not use the disk space two times. qBittorrent stops to seed at ratio 1 or after 24 hours.
Then Sonarr or Radarr removes the torrent. The copy in the library stays.

### Add a movie or series

Family members use Seerr. Their guide is [movies-and-series.md](movies-and-series.md). Your requests,
and requests from users with *Auto-Approve* (Seerr → *Users*), start immediately. Other requests
wait under *Requests* until you approve them. Discord tells you about them. Discord also tells you
about the issues that users report.

**The sequence after a request:**

1. Radarr or Sonarr searches all indexers. It selects the best release that the quality profile
   permits. The TRaSH rules put good 1080p WEB and Blu-ray groups first. They block fakes,
   re-encodes and low quality.
2. qBittorrent downloads the release.
3. The import renames the file and hardlinks it into the library.
4. Jellyfin shows the title. Discord reports the import.
5. Bazarr adds subtitles, usually in less than one hour.

If no release is acceptable yet, the title stays on the wanted list. Radarr and Sonarr look for new
releases each 15 minutes and get the first release that is acceptable. If a better release comes
later, it replaces the file (an upgrade).

**Add a title directly in Radarr or Sonarr** (more options):

- Radarr → *Movies → Add New* → search. Set root folder `/media/movies`, profile *1080p*, monitor
  *Movie Only* and minimum availability *Released*. Select *Start search for missing movie*. Push
  *Add Movie*.
- Sonarr → *Series → Add New* → search. Set root folder `/media/shows`, profile *1080p* and monitor
  *All Episodes*. For only the episodes from now on, use *Future Episodes*. Set series type
  *Standard* (or *Anime* or *Daily*) and season folders on. Select *Start search for missing
  episodes*. Push *Add*.

**Select the release yourself:** On a movie, season or episode, open **Interactive Search** (the
person icon). It shows all releases, and the reason for each rejected release. Push the download
icon of a release. Use this for a special version, or when the automatic search finds no
acceptable release.

**Profiles:** The two apps have the same two profiles, from TRaSH-Guides through Configarr:

- **1080p** (default): movies from Blu-ray or WEB, series from WEB.
- **4K, else 1080p:** gets 2160p if a release exists, else 1080p. It upgrades to 2160p when a
  release becomes available.

To get a title in 4K, select **4K, else 1080p**. In Seerr, you find it in the request dialog under
*Advanced* (only for admins and users with advanced requests). Later, you can change it in Radarr or
Sonarr → the title → *Edit*. For other qualities (720p, HDTV, a remux, few seeders), use
*Interactive Search*.

The Pi cannot transcode 4K. Thus, 4K plays only on devices that decode 4K HEVC and HDR (the TV apps,
not most browsers or old phones). A 4K movie uses 15–60 GB.

**Language:** The profiles accept only the original language (an English movie in English). They
reject dubbed releases. Bazarr gives Czech and English subtitles. To permit dubbed releases, change
the language settings in `apps/media/configarr.yaml`.

**Files that you already have:**

1. Copy the files to the Pi with the naming from [setup.md](setup.md) (Jellyfin).
2. In Radarr, use *Movies → Library Import*. In Sonarr, use *Series → Library Import*. Select the
   root folder (`/media/movies` or `/media/shows`) and make sure that each title has the correct
   match.
3. Set the profile *1080p* and select the monitor option:
   - **Movie Only** (in Sonarr: *All Episodes* or *Last Season*): Radarr or Sonarr searches for a
     better release. If it finds one, it replaces your file. Use this for small or low-quality
     files.
   - **None:** Your files stay as they are. Radarr or Sonarr does not download anything for them.
     Use this if you want to keep a special version or dub.
4. Push *Import*.

After the import, Bazarr knows the titles and adds the missing subtitles. Bazarr works only on
titles that Sonarr or Radarr knows. Seerr shows the titles as available.

**Missing episodes of a series that you already have:** Seerr requests only full seasons. If
Jellyfin has a season partially, Seerr cannot request that season.

1. In Sonarr, import the series (*Library Import*). Set monitor to *Last Season* or *Missing
   Episodes*. Select *Start search for missing episodes*.
2. Sonarr keeps the existing files and downloads the missing episodes.
3. In Seerr, push *Settings → Jobs & Cache* → *Sonarr Scan* → *Run Now*.

**Delete a title:** In Radarr or Sonarr → the title → *Delete*. Select *Delete files*. If you
delete the title only in Jellyfin or on the disk, Radarr or Sonarr downloads it again. To let users
request the title again, use *Manage → Clear Data* on the title in Seerr.

### If a download does not start or stops

- **Indexers:** Add indexers by hand in Prowlarr. They are not in Git, because this repository is
  public. Prowlarr sends them to Sonarr and Radarr.
- **No download:** In Sonarr or Radarr, *Activity → Queue* shows the reason. *System → Status* shows
  broken indexers and download client failures. In Prowlarr, test each indexer under *Indexers*.
  Radarr and Sonarr put a failed download on the blocklist and search for a different release.
- **A download stops (stalled):** The release has too few seeders. In *Activity → Queue*, push ✕
  for the release. Select *Blocklist release* and *Search for a replacement*.
- **An indexer is missing in Radarr or Sonarr:** Radarr and Sonarr refuse an indexer if their test
  search finds nothing in their categories (movies 2000s, TV 5000s). The Prowlarr log then shows
  `400` for that app. Use an indexer that has that type of content.
- **The import fails with "hardlink" or "permission":** All pods run as UID 1000. `/srv/media` must
  belong to UID 1000. On the Pi, run `sudo chown -R 1000:1000 /srv/media`.
- **Settings change back:** Configarr does this. Change `apps/media/configarr.yaml` instead.

### VPN for qBittorrent (planned)

At this time, qBittorrent has no VPN. Peers in each swarm see the home IP address, and the ISP sees
which data qBittorrent downloads. The home connection is probably behind CGNAT. Thus, other peers
cannot connect to qBittorrent, and a port forward on the router cannot solve this.

**How a VPN solves this:**

```
┌ qBittorrent pod ─────────────────────────┐
│ qBittorrent ──► Gluetun ══WireGuard══════╪══► VPN server ──► peers
│                 (kill switch)            │      peers see the IP address of the VPN server
└──────────────────────────────────────────┘      the ISP sees only encrypted traffic
```

- [Gluetun](https://github.com/qdm12/gluetun) is a sidecar container in the qBittorrent pod
  (approximately 30–50 MB RAM). The two containers share one network. Thus, all traffic of
  qBittorrent goes through the WireGuard tunnel of Gluetun.
- **Kill switch:** The firewall of Gluetun blocks all traffic outside the tunnel. If the VPN is
  down, qBittorrent has no connection. It cannot use the home IP address.
- **Port forwarding:** The provider opens a port on its server and sends the traffic through the
  tunnel to qBittorrent. Then peers can connect to qBittorrent, also behind CGNAT.
- Only qBittorrent uses the VPN. All other apps use the normal connection.

**Provider:** The provider must have port forwarding. Mullvad and IVPN removed it in 2023. NordVPN
and Surfshark do not have it.

| Provider | Port forwarding | Notes |
|---|---|---|
| **ProtonVPN Plus** (recommended) | Automatic (NAT-PMP). The port changes at each connection. | Gluetun gets the port and sets it in qBittorrent automatically. Swiss, audited no-logs policy. |
| **AirVPN** (alternative) | Fixed. You select the port one time in the client area. | Popular for torrents. You set the port in qBittorrent one time. |
| Private Internet Access | Automatic | Low price. Based in the USA, owned by Kape. |

**Changes in the cluster:**

1. Make a new namespace `downloads` for qBittorrent and Gluetun. Gluetun needs the capability
   `NET_ADMIN`. The namespace `tv` has the Pod Security level baseline, which does not permit
   `NET_ADMIN`. Thus, only this pod gets a namespace with a higher level.
2. Add a second PersistentVolume for `/srv/media` with a PVC in `downloads`. The mount path stays
   `/media`. Thus, imports stay hardlinks.
3. Add Gluetun to the qBittorrent pod. Set `VPN_SERVICE_PROVIDER`, `VPN_TYPE=wireguard` and
   `VPN_PORT_FORWARDING=on`. For ProtonVPN, `VPN_PORT_FORWARDING_UP_COMMAND` sends the new port to
   the qBittorrent API on `127.0.0.1:8080` (`WebUI\LocalHostAuth=false` permits this).
4. Add a case `vpn` in `scripts/seal.sh` for the WireGuard private key (and the address, if the
   provider gives one).
5. In `apps/media/configarr.yaml`, change the qBittorrent host to `qbittorrent.downloads`.
6. Remove the LoadBalancer `qbittorrent-bt` and the router port forward, if one exists.
7. Optional: Gluetun has an HTTP proxy. Add it as an indexer proxy in Prowlarr (through Configarr).
   Then Prowlarr searches also go through the VPN. This helps if the ISP blocks torrent sites.

**Steps for the admin:**

1. Buy the subscription.
2. In the dashboard of the provider, make a WireGuard configuration. For ProtonVPN, select a P2P
   server and enable port forwarding.
3. Run `scripts/seal.sh vpn` and enter the private key.
4. Commit and push.

**Tests before use:**

- The IP address that peers see is the address of the VPN server, not the home IP address.
- Kill switch: Stop the VPN in Gluetun. qBittorrent must then have no connection.
- The forwarded port is open. qBittorrent shows the connection status as connected, not firewalled.

The Pi 5 can do WireGuard at several hundred Mbit/s. Thus, the Wi-Fi stays the limit, not the VPN.

## Add a second Pi

1. On the new board, do [setup.md](setup.md) step 3, up to and including the host scripts `01` and
   `02`. Use the name `rpi-02`. Without an SD card, `02-setup-pi.sh` stops at the backup-disk step.
   All steps before it are complete.
2. Join the Pi as an **agent**. One etcd member is sufficient. Two members are *worse* than one.
   ```bash
   ssh -t rpi 'sudo cat /var/lib/rancher/k3s/server/node-token'
   # on rpi-02
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.36.4+k3s1" \
     K3S_URL=https://192.168.50.244:6443 K3S_TOKEN=<token> sh -s - agent --node-name rpi-02
   ```
3. Workloads with a `local-path` volume stay on rpi-01, because each volume is on one node. AdGuard
   is pinned to rpi-01. The second cloudflared replica, Immich machine learning and stateless
   workloads can move to rpi-02.

rpi-02 can also keep a second copy of `/srv/backup`, or a second AdGuard that
[adguardhome-sync](https://github.com/bakito/adguardhome-sync) keeps in sync.

A highly available control plane needs three servers. Two nodes give more capacity, but not more
availability.

## Troubleshooting

| Symptom | Cause / solution |
|---|---|
| App `argocd` stops at *waiting for deletion of hook … argocd-redis-secret-init* | The bootstrap `helm install` made these objects. Argo CD does not delete objects that it does not own. Run `kubectl -n argocd delete job,rolebinding,role,serviceaccount argocd-redis-secret-init`. |
| App `platform` stays *Progressing* after the bootstrap | Its SealedSecrets cannot be decrypted yet ([setup.md, step 6](setup.md#6-argo-cd-and-secrets)). |
| cloudflared is *Running*, but the sites give 1033/530 | No connection to the edge. Possibly outbound UDP 7844 (QUIC) is blocked. Add `--protocol http2` to its arguments. |
| Pods are OOM-killed, but the limits are correct | The memory cgroup is not enabled. Run `grep memory /sys/fs/cgroup/cgroup.controllers`. |
| AdGuard CrashLoop: `bind: address already in use` | A process on the host uses port 53 (`ss -lunp`), or the web UI uses port 80, which belongs to Traefik. |
| Vaultwarden: "not a secure context … Subtle Crypto API" | You opened it with `http://`. Use `https://`. |
| Grafana restarts, and the kernel log shows `gpx_grafana-*` killed | Its plugin processes used more memory than the limit. Increase the limit in `argocd/10-kube-prometheus-stack.yaml`. |
| Discord alerts fail: `unsupported protocol scheme` | The pasted webhook URL has an unwanted character. Run `scripts/seal.sh alertmanager-notify` again. |
| Changes do not show on `lichnovsky.eu` | The edge cache of Cloudflare. Send `Cache-Control`, or purge the cache in the dashboard. |
| A certificate stays at `Issuing` | The cert-manager token needs *Zone:DNS:Edit* on `lichnovsky.eu`. |
| The Bitwarden app shows "cannot connect" only away from home | Access is on the full `vault.` host, not only on `/admin`. |
| Backups fail, and the rest-server pod is `Pending` | The SD card is not mounted (`findmnt /srv/backup`). Install the card again and run `sudo mount /srv/backup`. |
| A large upload fails away from home, but works at home | The 100 MB request limit of Cloudflare. Use Tailscale. |
