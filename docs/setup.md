# Setup

Building everything from zero, in order: for a rebuild after a lost SSD, a second Pi, or to see what
was done by hand once. After step 6, Argo CD deploys the rest from Git. Why things are built this way
is in [architecture.md](architecture.md).

| Step | Where | Result |
|---|---|---|
| [1. Accounts](#1-accounts) | browser | Cloudflare, Tailscale, GitHub and Discord ready |
| [2. Workstation](#2-workstation) | laptop | tools, credentials file, SSH alias, git hooks |
| [3. The Pi](#3-the-pi) | Pi | OS on NVMe, host prepared, SD card as backup disk, k3s running |
| [4. kubeconfig](#4-kubeconfig) | laptop | `kubectl` talks to the cluster |
| [5. Cloudflare](#5-cloudflare) | laptop | tunnel, DNS, Access, DNSSEC, heartbeat |
| [6. Argo CD and secrets](#6-argo-cd-and-secrets) | laptop | everything deploys from Git |
| [7. LAN and remote access](#7-lan-and-remote-access) | browser, router | app names resolve at home and over Tailscale |
| [8. First run of each app](#8-first-run-of-each-app) | browser | admin accounts, settings |
| [9. Done when](#9-done-when) | laptop | everything verified |

Values used throughout: Pi `rpi-01` at `192.168.50.244`, domain `lichnovsky.eu`, repo
`git@github.com:JersyJ/lichnovsky.git`. Commands marked *on the Pi* run there; everything else runs on
the laptop in the repo folder.

## 1. Accounts

### Cloudflare
1. **Move the domain's DNS to Cloudflare.** The registrar (Porkbun) stays; only the nameservers
   change. **First turn DNSSEC off at Porkbun**, or the domain stops resolving after the switch
   (step 5 turns it back on). Cloudflare → *Connect a domain* → `lichnovsky.eu` → Free plan. Delete
   the registrar's parking records it offers to import, then set Cloudflare's two nameservers at
   Porkbun. Wait until Cloudflare shows the domain as *Active*.
2. **R2, API tokens and Zero Trust for OpenTofu:** the one-time dashboard steps in
   [cloudflare/README.md](../cloudflare/README.md).
3. **API token for cert-manager:** My Profile → API Tokens → *Create Token* → template *Edit zone DNS*
   → zone `lichnovsky.eu` only. Keep it for step 6. It's made by hand, not in OpenTofu, because
   creating tokens from code needs a token that can mint tokens, which is effectively full control
   of the account.

### Tailscale
1. Free Personal plan; log in with any identity provider.
2. Admin console → **Access controls**, add to the policy file (keep the rest):
   ```jsonc
   "tagOwners": {
     "tag:k8s-operator": ["autogroup:admin"],
     "tag:k8s": ["tag:k8s-operator"],
   },
   "autoApprovers": {
     "routes": { "192.168.50.244/32": ["tag:k8s"] },
   },
   ```
   `autoApprovers` approves the Pi's route automatically, so nothing has to be clicked after deploy.
3. **Settings → Trust credentials → OAuth client:** scopes *General → Services*, *Devices → Core*,
   *Keys → Auth Keys* (Read + Write each), tag `tag:k8s-operator`. Keep the client ID and secret for
   step 6. Scopes change between releases; check the
   [operator docs](https://tailscale.com/kb/1236/kubernetes-operator) if these don't match.

### GitHub
A private repository `JersyJ/lichnovsky` with this folder pushed to it. Argo CD reads it with a
read-only deploy key (created in step 6).

The website image is built by GitHub Actions on the first push that touches `web/`. GHCR makes a
new package private, so once, after that first build: GitHub → your profile → *Packages* →
`lichnovsky-web` → *Package settings* → *Change visibility* → **Public**. The image only holds the
public website; the repository stays private.

### Discord
A private channel (e.g. `#homelab`) → Edit Channel → Integrations → Webhooks → *New Webhook* → copy
the URL. Alertmanager, Argo CD and the heartbeat Worker all post there.

## 2. Workstation

1. **Tools:** `kubectl`, `kubeseal` (same minor version as the Sealed Secrets controller), `helm`,
   `kubeconform`, `openssl`, `ssh`, `dig`, [prek](https://github.com/j178/prek) and OpenTofu through
   [tenv](https://github.com/tofuutils/tenv) (`tenv tofu install` reads `.opentofu-version`).
2. **Git hooks:** `prek install` in the repo.
3. **Cloudflare credentials:** `~/.config/lichnovsky/cloudflare.env`, readable only by you
   (`chmod 600`), exporting the variables listed in [cloudflare/README.md](../cloudflare/README.md).
   Keep a copy in the password manager.
4. **SSH alias** in `~/.ssh/config`, so every command below can say `rpi`:
   ```
   Host rpi rpi-01
     HostName 192.168.50.244
     User <your user>
   ```

## 3. The Pi

### Hardware
- Raspberry Pi 5, 8 GB, with the **official 27 W USB-C power supply**; weaker ones cause brown-outs
  under load.
- **Active Cooler** or a case with a fan: the Pi throttles at 80 °C (the temperature alert fires at 75 °C).
- **NVMe SSD** on an M.2 HAT: system, app data and media.
- **128 GB microSD card:** the backup disk. A second device, so one dead SSD doesn't take the
  backups with it. "High Endurance" cards cope best with nightly writes.

### Operating system
1. **Flash** Raspberry Pi OS Lite (64-bit, Trixie) with Raspberry Pi Imager directly onto the NVMe
   (USB adapter). In Imager's settings: your user, your SSH public key, password login off, Wi-Fi,
   time zone Europe/Prague. The hostname can be anything; the first host script renames it.
2. **Boot from NVMe**, *on the Pi*: `sudo rpi-eeprom-config --edit` → `BOOT_ORDER=0xf416` (NVMe →
   SD → USB). Optional and faster, but officially "not certified": PCIe Gen 3 with
   `dtparam=pciex1_gen=3` in `/boot/firmware/config.txt`.
3. **Reserve the IP** `192.168.50.244` for the Pi in the router's DHCP. Ethernet is better than
   Wi-Fi (copies run at ~13 MB/s over Wi-Fi). The Pi itself resolves through 9.9.9.9 and 1.1.1.1,
   **not** AdGuard (set by `02-setup-pi.sh`): CoreDNS would otherwise depend on a pod that isn't
   running yet at boot.
4. **Swap:** Trixie ships a 2 GB zram swap, which is fine (pods don't swap). Don't add a swapfile
   on the SSD.

### Host scripts
What each file does: [host/README.md](../host/README.md). `sudo` needs a real terminal, so run
these yourself:
```bash
ssh rpi 'mkdir -p ~/lichnovsky-setup' && scp host/* rpi:lichnovsky-setup/
ssh -t rpi 'sudo bash ~/lichnovsky-setup/01-set-hostname.sh rpi-01 && sudo reboot'
ssh -t rpi 'sudo bash ~/lichnovsky-setup/02-setup-pi.sh 2>&1 | tee ~/lichnovsky-setup/setup.log && sudo reboot'
```
Check after the reboot; it must print `memory`, the mounted SD card and `rpi-01`:
```bash
ssh rpi 'grep -o memory /sys/fs/cgroup/cgroup.controllers; findmnt /srv/backup; hostname'
```
Then install k3s:
```bash
ssh -t rpi 'sudo bash ~/lichnovsky-setup/03-install-k3s.sh'
```
It ends with the node `Ready` and prints how to read the **k3s server token**. Save that token in
the password manager: restoring an etcd snapshot needs it.

Finally, *on the Pi*:
- `sudo chown "$USER": /srv/media`, so you can copy media there (UID 1000, the UID Jellyfin reads with).
- `sudo ss -lunp | grep ':53 '` must print nothing: AdGuard needs port 53.

## 4. kubeconfig

The admin kubeconfig is root-only on the Pi. Copy it over (no `ssh -t` for the second command: it
would turn the line endings into CRLF) and name the context `lichnovsky`:
```bash
ssh -t rpi 'mkdir -p ~/.kube && sudo install -m 0600 -o "$USER" /etc/rancher/k3s/k3s.yaml ~/.kube/config'
(umask 077; mkdir -p ~/.kube && ssh rpi 'cat ~/.kube/config' > ~/.kube/config)
sed -i 's#127.0.0.1#192.168.50.244#; s/\bdefault\b/lichnovsky/g' ~/.kube/config
kubectl get nodes -o wide     # rpi-01 Ready
```
Step 7 switches the server to `k8s.lichnovsky.eu` once AdGuard answers for it.

## 5. Cloudflare

```bash
source ~/.config/lichnovsky/cloudflare.env
tofu -chdir=cloudflare init
tofu -chdir=cloudflare apply
```
This creates the tunnel with its public hostnames, the DNS records, Access, the rate limit and
cache rule, the TLS settings, DNSSEC and the heartbeat Worker. It comes before step 6 because
`seal.sh cloudflared-token` reads the tunnel token from OpenTofu.

**DNSSEC at Porkbun** (lichnovsky.eu → DNSSEC), once: enter the output of
`tofu -chdir=cloudflare output dnssec_keydata` (flags 257, protocol 3, algorithm 13, public key)
and leave *Max Sig Life* empty. Check after an hour: `dig +dnssec lichnovsky.eu @1.1.1.1` shows the
`ad` flag.

## 6. Argo CD and secrets

### Install Argo CD
Installed with the same values it later uses to manage itself:
```bash
helm install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.9.2 \
  -n argocd --create-namespace -f bootstrap/argocd-values.yaml
```

### Repository access
A read-only deploy key: scoped to this one repo, not tied to your account, no expiry.
```bash
ssh-keygen -t ed25519 -N '' -C argocd@lichnovsky.eu -f ~/.config/lichnovsky/argocd-deploy-key
#   GitHub -> JersyJ/lichnovsky -> Settings -> Deploy keys -> Add: the .pub, "Allow write access" OFF
kubectl -n argocd create secret generic repo-lichnovsky \
  --from-literal=type=git --from-literal=url=git@github.com:JersyJ/lichnovsky.git \
  --from-file=sshPrivateKey=$HOME/.config/lichnovsky/argocd-deploy-key
kubectl -n argocd label secret repo-lichnovsky argocd.argoproj.io/secret-type=repository
```
Keep the private key in the password manager too.

### Sealed Secrets key
The SealedSecrets in Git decrypt only with the key they were sealed for.
- **Rebuild with the saved key:** apply it now, before handing over to Git:
  `kubectl apply -f sealed-secrets-key.backup.yaml`. Everything in Git decrypts as before, including
  the backup passwords, so existing backups stay readable. Then skip the sealing below.
- **Brand-new cluster:** hand over to Git first, then seal every secret (below). Backups made
  under an old key stay encrypted with the old restic password.

### Hand over to Git
```bash
kubectl apply -f bootstrap/root.yaml
kubectl -n argocd get applications -w
```
Argo CD installs everything wave by wave. On a brand-new cluster, wave -8 (`platform`) waits until
its secrets can be decrypted. If the `argocd` app hangs at *waiting for deletion of hook …
argocd-redis-secret-init*, see [operations.md → Troubleshooting](operations.md#troubleshooting).

### Seal the secrets (brand-new cluster only)
Wait for the controller, load the Cloudflare credentials, then run `scripts/seal.sh <name>` for each:
```bash
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
source ~/.config/lichnovsky/cloudflare.env
```

| Name | Asks for | Notes |
|---|---|---|
| `cloudflare-api-token` | the cert-manager token from step 1 | |
| `cloudflared-token` | nothing | read from `tofu output` |
| `grafana-admin` | nothing | prints the password once: save it |
| `alertmanager-notify` | the Discord webhook URL | rejects anything that isn't a Discord webhook |
| `argocd-notifications` | the same Discord webhook URL | |
| `tailscale-operator-oauth` | the OAuth client ID and secret from step 1 | |
| `vaultwarden` | an argon2 hash of the admin page password | make it with `kubectl run vw-hash --rm -it --restart=Never --image=vaultwarden/server:1.37.3 -- /vaultwarden hash` |
| `papra` | nothing | |
| `media` | nothing | API keys for Sonarr/Radarr/Prowlarr and qBittorrent's password; prints the qBittorrent login once: save it |
| `backups` | nothing | prints the **restic password** once: save it in the password manager and on paper. Refuses to run if backup secrets already exist |

Values never touch the disk or a command line; they reach `kubeseal` through stdin. Commit the
`sealed-*.yaml` files and push; Argo CD picks them up within ~3 minutes.

### After the first sync
1. **Back up the Sealed Secrets key** into the password manager, then delete the file. The key
   rotates every 30 days (old keys are kept), so repeat this now and then:
   ```bash
   (umask 077; kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
     -o yaml > ~/sealed-secrets-key.backup.yaml)
   ```
2. **Argo CD admin password:**
   `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
   Log in at `https://argocd.lichnovsky.eu`, change it under *User Info*, then
   `kubectl -n argocd delete secret argocd-initial-admin-secret`.

## 7. LAN and remote access

### AdGuard Home
1. Open `http://192.168.50.244:3000` for the setup wizard. Web interface: *all interfaces, port
   3000*; DNS server: *all interfaces, port 53*. Ports 80/443 belong to Traefik. Create the admin.
2. **Filters → DNS rewrites:** `lichnovsky.eu` → `192.168.50.244` and `*.lichnovsky.eu` →
   `192.168.50.244`. If a subdomain is ever hosted elsewhere, add a more specific rewrite for it.
3. **Settings → DNS settings → Upstream DNS servers:** DoH, e.g. `https://dns.quad9.net/dns-query`
   and `https://cloudflare-dns.com/dns-query`; select *Parallel requests*; keep the cache on.
4. **Test it directly**, before switching the house over:
   ```bash
   dig +short @192.168.50.244 tv.lichnovsky.eu      # 192.168.50.244
   dig +short @192.168.50.244 github.com            # a public address
   dig +short @192.168.50.244 doubleclick.net       # 0.0.0.0 (blocked)
   ```
5. **Router → DHCP → DNS servers:** `192.168.50.244` first, `9.9.9.9` second. The second one keeps
   the house online when the Pi reboots (without ad blocking; clients may also use it at other
   times, so some ads get through). On ASUS, set *Advertise router's IP in addition to
   user-specified DNS* to **No**. Leave the router's own WAN DNS alone: pointed at the Pi, the
   router couldn't resolve anything while the Pi is down.
6. Switch kubectl to the name: `kubectl config set-cluster lichnovsky --server=https://k8s.lichnovsky.eu:6443`.
   It resolves only through AdGuard and Tailscale, and keeps working if the Pi's IP changes.

### Tailscale
1. After the operator has synced, the admin console shows `lichnovsky-k8s-operator` and
   `lichnovsky-lan` with the route `192.168.50.244/32` already approved.
2. **DNS → Nameservers → Add nameserver → Custom:** `192.168.50.244`, enable **Restrict to domain**
   → `lichnovsky.eu` (split DNS: only these names go to AdGuard).
3. **Clients:** phones accept routes automatically. Linux ignores them by default:
   `sudo tailscale set --accept-routes`.
4. **Test from a phone on mobile data** (Wi-Fi off): `https://dns.lichnovsky.eu` has no public
   record, so if it loads, remote access works end to end.

## 8. First run of each app

Do this right after the first deploy: whoever opens a fresh app first becomes its admin, and on
the LAN nothing stands in front of it.

**Vaultwarden** (`https://vault.lichnovsky.eu`)
1. `/admin` → Cloudflare Access (on the internet), then the admin page password whose hash was sealed.
2. *Users → Invite user* with your e-mail. There's no SMTP, so no mail is sent: register at
   `https://vault.lichnovsky.eu` with that address.
3. Choose the **master password**. It encrypts the vault and **nobody can reset it**: write it down
   offline. Turn on two-step login and keep the recovery code with the master password.
4. Clients: Bitwarden apps and browser extension → *self-hosted* → `https://vault.lichnovsky.eu`.

**Papra** (`https://papra.lichnovsky.eu`): registration is closed in the manifest. On a brand-new
install (no restored data), set `AUTH_IS_REGISTRATION_ENABLED` to `"true"` in
`apps/papra/papra.yaml`, push, create the first account (it becomes the owner), then set it back to
`"false"` and push.

**Uptime Kuma** (`https://status.lichnovsky.eu`)
1. The first screen creates the admin.
2. Monitors: one HTTP monitor per app URL, a DNS monitor against `192.168.50.244` for AdGuard.
3. Settings → Notifications → Discord, with the same webhook URL; attach it to the monitors.
4. **Status Pages → New status page**, slug **`home`**: public at
   `https://status.lichnovsky.eu/status/home`, and the website's status widget reads it. Only
   monitors you add to the page are shown.

**Grafana** (`https://grafana.lichnovsky.eu`)
`kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`,
log in as `admin`, change it under *Profile*. The *Homelab* folder holds the tunnel, Traefik, Argo
CD and logs dashboards; *Node Exporter / Nodes* shows the Pi itself.

**Jellyfin** (`https://tv.lichnovsky.eu`, home and Tailscale only)
1. Wizard: create the admin; keep *Allow remote connections* **on** (everything arrives through
   Traefik, so Jellyfin can't tell local from remote; the private hostname is the protection) and
   *automatic port mapping* **off**.
2. Dashboard → Playback: hardware acceleration **off** (the Pi 5 has no video encoder), and a high
   *Internet streaming bitrate limit*, so remote clients don't transcode because of bitrate.
3. Libraries: Movies → `/media/movies`, Shows → `/media/shows`, Music → `/media/music`. Turn on
   real-time monitoring. Turn **off** *Save artwork into media folders* and *Save metadata as NFO*
   (media is mounted read-only), and **off** chapter image extraction and trickplay (they decode
   every video in full: hours of CPU per movie). Leave *Prefer embedded titles* off.
4. Media layout and copying:
   ```
   movies/Title (Year)/Title (Year).mkv
   movies/Title (Year)/Title (Year).cs.srt
   shows/Show (Year)/Season 01/Show S01E01.mkv
   ```
   ```bash
   rsync -ah --mkpath --info=progress2 file.mkv "rpi:/srv/media/movies/Title (Year)/Title (Year).mkv"
   ```
   Check codecs first with `ffprobe`: H.264/AAC plays everywhere; HEVC 10-bit plays in the Jellyfin
   apps but not in many browsers, which forces a CPU transcode (about one 1080p stream at most).

**Media stack** (all home and Tailscale only). Do it in this order; each app's address is in the
[README](../README.md). Inside the cluster the apps reach each other by short name (`http://sonarr`,
port 80), which is what goes into the forms below.

1. **Sonarr, Radarr, Prowlarr:** open each; the first screen asks for an authentication method:
   *Forms (Login Page)*, *Required: Enabled*, and a username and password (save them).
2. **Configarr:** run it once instead of waiting for :17, and check it ends with no errors:
   ```bash
   kubectl -n tv create job --from=cronjob/configarr configarr-now
   kubectl -n tv logs -f job/configarr-now
   ```
   Sonarr now has the *WEB-1080p* profile, Radarr *HD Bluray + WEB*, both have the root folder and
   qBittorrent as download client (*Settings → Download Clients → Test* is green), and Prowlarr lists
   Sonarr and Radarr under *Settings → Apps*.
3. **Prowlarr → Indexers → Add Indexer:** add the ones you use and press *Test*. An indexer behind a
   Cloudflare check needs the tag `flaresolverr`. *Sync App Indexers* (or wait a few minutes) and
   they appear in Sonarr/Radarr under *Settings → Indexers*.
4. **qBittorrent:** log in as `admin` with the password `seal.sh media` printed. Nothing to change:
   downloads go to `/media/downloads`, seeding stops at ratio 1 or after 24 h.
5. **Bazarr:** create the login (*Settings → General → Security → Forms*), then:
   - *Settings → Languages:* a profile, e.g. Czech + English; set it as the default for series and
     movies.
   - *Settings → Providers:* OpenSubtitles.com (free account), Podnapisi, and any others you like.
   - *Settings → Library → Sonarr:* tick *Enabled*, address `sonarr`, port `80`, API key from Sonarr
     (*Settings → General*). *Radarr* tab: `radarr`, `80`, Radarr's key. No path mappings: paths
     are the same everywhere.
   - *Settings → Integrations → Jellyfin:* *Enabled*, server URL `http://jellyfin`, an API key from
     Jellyfin (*Dashboard → API Keys*), refresh *Immediate*; pick both libraries and tick their
     refresh boxes, so new subtitles show up in Jellyfin at once.
6. **Seerr** (`https://watchlist.lichnovsky.eu`): choose *Jellyfin* and sign in with the Jellyfin
   admin (Jellyfin URL `http://jellyfin`, port `80`; external URL `https://tv.lichnovsky.eu`).
   Sync the libraries (Movies, Shows). Then *Radarr server*: `radarr`, port `80`, Radarr's API key,
   profile *HD Bluray + WEB*, root folder `/media/movies`, external URL `https://radarr.lichnovsky.eu`,
   *Default server* on. *Sonarr server* the same with `sonarr`, *WEB-1080p*, `/media/shows`, season
   folders on. Family members sign in with their Jellyfin accounts; give them *Auto-approve* under
   *Users* if requests shouldn't wait for you.
7. **Optional:**
   - Discord: Sonarr/Radarr *Settings → Connect → Discord* and Seerr *Settings → Notifications →
     Discord*, with the alerts webhook.
   - Router: forward port `50413` TCP+UDP to `192.168.50.244` for incoming peers (faster, more
     sources). Only with a public IPv4: behind CGNAT (the router's WAN IP is `10.x`/`100.64.x`) a
     forward can't work; a VPN with port forwarding solves it ([operations.md](operations.md#media-stack)).
   - Uptime Kuma: monitors for the stack must use in-cluster URLs, as the names are private:
     `http://seerr.tv.svc.cluster.local/api/v1/status`, `http://sonarr.tv.svc.cluster.local/ping`.

Test: request a movie in Seerr. It appears in Radarr, then in qBittorrent, and after the download
in Jellyfin; Bazarr adds subtitles within the hour.

**AdGuard Home** was set up in step 7.

## 9. Done when

```bash
kubectl -n argocd get applications              # all Synced / Healthy
kubectl get certificate -A                      # wildcard-lichnovsky-eu Ready
curl -sI https://lichnovsky.eu | head -1        # HTTP/2 200
```
- A test alert reaches Discord ([operations.md → Alerts](operations.md#alerts)).
- The next morning, every backup has a fresh snapshot, and there's a restore test on the calendar
  ([operations.md → Backups](operations.md#backups)).
- In the password manager: the Cloudflare credentials file, deploy key, Sealed Secrets key, k3s
  server token, restic password, Grafana and Argo CD passwords. On paper: the Vaultwarden master
  password with its recovery code, and the restic password.
