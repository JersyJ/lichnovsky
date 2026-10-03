# Setup

This document tells you how to build the full system from zero, in sequence. Use it to build again
after the loss of an SSD, for a second Pi, or to see which steps were done by hand. After step 6,
Argo CD deploys all other components from Git. For the reasons behind the design, refer to
[architecture.md](architecture.md).

| Step | Location | Result |
|---|---|---|
| [1. Accounts](#1-accounts) | Browser | Cloudflare, Tailscale, GitHub and Discord are ready |
| [2. Workstation](#2-workstation) | Laptop | Tools, credentials file, SSH alias, Git hooks |
| [3. The Pi](#3-the-pi) | Pi | OS on the NVMe, host prepared, SD card as backup disk, k3s runs |
| [4. kubeconfig](#4-kubeconfig) | Laptop | `kubectl` connects to the cluster |
| [5. Cloudflare](#5-cloudflare) | Laptop | Tunnel, DNS, Access, DNSSEC, heartbeat |
| [6. Argo CD and secrets](#6-argo-cd-and-secrets) | Laptop | Argo CD deploys all components from Git |
| [7. LAN and remote access](#7-lan-and-remote-access) | Browser, router | The app names resolve at home and through Tailscale |
| [8. First run of each app](#8-first-run-of-each-app) | Browser | Admin accounts, settings |
| [9. Final checks](#9-final-checks) | Laptop | All components are verified |

This document uses these values: Pi `rpi-01` at `192.168.50.244`, domain `lichnovsky.eu`,
repository `git@github.com:JersyJ/lichnovsky.git`. Run the commands with the label *on the Pi* on
the Pi. Run all other commands on the laptop, in the repository folder.

## 1. Accounts

### Cloudflare

1. **Move the DNS of the domain to Cloudflare.** The registrar (Porkbun) stays. Only the name
   servers change.
   1. **First, turn off DNSSEC at Porkbun.** If you do not, the domain does not resolve after the
      change. Step 5 turns DNSSEC on again.
   2. In Cloudflare, push *Connect a domain*. Enter `lichnovsky.eu` and select the Free plan.
   3. Delete the parking records of the registrar that Cloudflare offers to import.
   4. Set the two Cloudflare name servers at Porkbun.
   5. Wait until Cloudflare shows the domain as *Active*.
2. **R2, API tokens and Zero Trust for OpenTofu:** Do the one-time dashboard steps in
   [cloudflare/README.md](../cloudflare/README.md).
3. **API token for cert-manager:** Go to My Profile → API Tokens → *Create Token*. Select the
   template *Edit zone DNS*, only for the zone `lichnovsky.eu`. Keep the token for step 6.

   You make this token by hand, not with OpenTofu. To make tokens from code, you need a token that
   can make tokens. Such a token has almost full control of the account.

### Tailscale

1. Get the free Personal plan. Log in with an identity provider.
2. In the admin console, open **Access controls**. Add this to the policy file and keep the other
   content:
   ```jsonc
   "tagOwners": {
     "tag:k8s-operator": ["autogroup:admin"],
     "tag:k8s": ["tag:k8s-operator"],
   },
   "autoApprovers": {
     "routes": { "192.168.50.244/32": ["tag:k8s"] },
   },
   ```
   `autoApprovers` approves the route of the Pi automatically. Thus, you do not have to approve it
   after the deployment.
3. Go to **Settings → Trust credentials → OAuth client**. Set the scopes *General → Services*,
   *Devices → Core* and *Keys → Auth Keys* (Read and Write for each). Set the tag
   `tag:k8s-operator`. Keep the client ID and the secret for step 6.

   The scopes can change between releases. If they are different, refer to the
   [operator documents](https://tailscale.com/kb/1236/kubernetes-operator).

### GitHub

Make the public repository `JersyJ/lichnovsky` and push this folder to it. Argo CD reads the
repository with a read-only deploy key (you make it in step 6).

GitHub Actions builds the website image on the first push that changes `web/`. GHCR makes a new
package private. After that first build, do this one time:

1. Go to GitHub → your profile → *Packages* → `lichnovsky-web` → *Package settings*.
2. Push *Change visibility* and select **Public**.

### Discord

1. Make a private channel (for example `#homelab`).
2. Go to Edit Channel → Integrations → Webhooks → *New Webhook*.
3. Copy the URL.

Alertmanager, Argo CD, the heartbeat Worker and the media apps send their messages to this channel.

## 2. Workstation

1. **Tools:** Install `kubectl`, `kubeseal`, `helm`, `kubeconform`, `openssl`, `ssh`, `dig`,
   [prek](https://github.com/j178/prek), and OpenTofu through
   [tenv](https://github.com/tofuutils/tenv). Use the same minor version of `kubeseal` as the
   Sealed Secrets controller. `tenv tofu install` reads `.opentofu-version`.
2. **Git hooks:** In the repository, run `prek install`.
3. **Cloudflare credentials:** Make the file `~/.config/lichnovsky/cloudflare.env`. Only you must be
   able to read it (`chmod 600`). The file exports the variables in
   [cloudflare/README.md](../cloudflare/README.md). Keep a copy in the password manager.
4. **SSH alias:** Add this to `~/.ssh/config`. The commands below use the name `rpi`.
   ```
   Host rpi rpi-01
     HostName 192.168.50.244
     User <your user>
   ```

## 3. The Pi

### Hardware

- Raspberry Pi 5, 8 GB, with the **official 27 W USB-C power supply**. Weaker power supplies cause
  brown-outs under load.
- **Active Cooler** or a case with a fan. The Pi decreases its speed at 80 °C. The temperature
  alert starts at 75 °C.
- **NVMe SSD** on an M.2 HAT, for the system, the app data and the media.
- **128 GB microSD card** as the backup disk. It is a second device. Thus, if the SSD breaks, the
  backups stay safe. "High Endurance" cards are best for writes each night.

### Operating system

1. **Write the image:** Use Raspberry Pi Imager to write Raspberry Pi OS Lite (64-bit, Trixie)
   directly onto the NVMe (with a USB adapter). In the Imager settings, set your user, your SSH
   public key, password login off, Wi-Fi and the time zone Europe/Prague. The hostname is not
   important, because the first host script changes it.
2. **Boot from the NVMe:** *On the Pi*, run `sudo rpi-eeprom-config --edit` and set
   `BOOT_ORDER=0xf416` (NVMe → SD → USB).

   PCIe Gen 3 is optional and faster, but it is "not certified". To use it, add
   `dtparam=pciex1_gen=3` to `/boot/firmware/config.txt`.
3. **Reserve the IP address** `192.168.50.244` for the Pi in the DHCP of the router. Ethernet is
   better than Wi-Fi. Over Wi-Fi, copies run at approximately 13 MB/s.

   The Pi uses 9.9.9.9 and 1.1.1.1 for DNS, **not** AdGuard (`02-setup-pi.sh` sets this). If the Pi
   used AdGuard, CoreDNS would need a pod that does not run yet at boot.
4. **Swap:** Trixie has a 2 GB zram swap. This is correct, because pods do not swap. Do not add a
   swapfile on the SSD.

### Host scripts

For the function of each file, refer to [host/README.md](../host/README.md). `sudo` needs a real
terminal. Thus, run these commands yourself:

```bash
ssh rpi 'mkdir -p ~/lichnovsky-setup' && scp host/* rpi:lichnovsky-setup/
ssh -t rpi 'sudo bash ~/lichnovsky-setup/01-set-hostname.sh rpi-01 && sudo reboot'
ssh -t rpi 'sudo bash ~/lichnovsky-setup/02-setup-pi.sh 2>&1 | tee ~/lichnovsky-setup/setup.log && sudo reboot'
```

After the reboot, do this check. The output must show `memory`, the mounted SD card and `rpi-01`:

```bash
ssh rpi 'grep -o memory /sys/fs/cgroup/cgroup.controllers; findmnt /srv/backup; hostname'
```

Then install k3s:

```bash
ssh -t rpi 'sudo bash ~/lichnovsky-setup/03-install-k3s.sh'
```

At the end, the node is `Ready`, and the script shows how to read the **k3s server token**. Keep the
token in the password manager. You need it to restore an etcd snapshot.

Then, *on the Pi*:

1. Run `sudo chown "$USER": /srv/media`. Then you can copy media to the folder. Your user is UID
   1000, which is the same UID that Jellyfin uses.
2. Run `sudo ss -lunp | grep ':53 '`. The command must show nothing, because AdGuard needs port 53.

## 4. kubeconfig

On the Pi, only root can read the admin kubeconfig. Copy it to the laptop, and name the context
`lichnovsky`. Do not use `ssh -t` for the second command, because it changes the line endings to
CRLF.

```bash
ssh -t rpi 'mkdir -p ~/.kube && sudo install -m 0600 -o "$USER" /etc/rancher/k3s/k3s.yaml ~/.kube/config'
(umask 077; mkdir -p ~/.kube && ssh rpi 'cat ~/.kube/config' > ~/.kube/config)
sed -i 's#127.0.0.1#192.168.50.244#; s/\bdefault\b/lichnovsky/g' ~/.kube/config
kubectl get nodes -o wide     # rpi-01 Ready
```

When AdGuard answers for `k8s.lichnovsky.eu`, step 7 changes the server to that name.

## 5. Cloudflare

```bash
source ~/.config/lichnovsky/cloudflare.env
tofu -chdir=cloudflare init
tofu -chdir=cloudflare apply
```

OpenTofu makes the tunnel with its public hostnames, the DNS records and Access. It also makes the
rate limit, the cache rule, the TLS settings, DNSSEC and the heartbeat Worker. Do this step before
step 6, because
`seal.sh cloudflared-token` reads the tunnel token from OpenTofu.

**DNSSEC at Porkbun** (one time):

1. Go to lichnovsky.eu → DNSSEC at Porkbun.
2. Enter the output of `tofu -chdir=cloudflare output dnssec_keydata` (flags 257, protocol 3,
   algorithm 13, public key). Keep *Max Sig Life* empty.
3. After one hour, run `dig +dnssec lichnovsky.eu @1.1.1.1`. The output must show the `ad` flag.

## 6. Argo CD and secrets

### Install Argo CD

Install Argo CD with the same values that it uses later to manage itself:

```bash
helm install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.9.2 \
  -n argocd --create-namespace -f bootstrap/argocd-values.yaml
```

### Repository access

Argo CD uses a read-only deploy key. The key is only for this repository, is not related to your
account, and does not expire.

```bash
ssh-keygen -t ed25519 -N '' -C argocd@lichnovsky.eu -f ~/.config/lichnovsky/argocd-deploy-key
#   GitHub -> JersyJ/lichnovsky -> Settings -> Deploy keys -> Add: the .pub, "Allow write access" OFF
kubectl -n argocd create secret generic repo-lichnovsky \
  --from-literal=type=git --from-literal=url=git@github.com:JersyJ/lichnovsky.git \
  --from-file=sshPrivateKey=$HOME/.config/lichnovsky/argocd-deploy-key
kubectl -n argocd label secret repo-lichnovsky argocd.argoproj.io/secret-type=repository
```

Also keep the private key in the password manager.

### Sealed Secrets key

The SealedSecrets in Git decrypt only with the key that sealed them.

- **Build again with the saved key:** Apply the key now, before you give control to Git:
  `kubectl apply -f sealed-secrets-key.backup.yaml`. All secrets in Git then decrypt as before, also
  the backup passwords. Thus, you can read the existing backups. Do not do the sealing steps below.
- **New cluster:** First give control to Git. Then seal all secrets (below). Backups that you made
  with an old key stay encrypted with the old restic password.

### Give control to Git

```bash
kubectl apply -f bootstrap/root.yaml
kubectl -n argocd get applications -w
```

Argo CD installs all components, wave by wave. On a new cluster, wave -8 (`platform`) waits until
it can decrypt its secrets. If the `argocd` app stops at *waiting for deletion of hook …
argocd-redis-secret-init*, refer to [operations.md → Troubleshooting](operations.md#troubleshooting).

### Seal the secrets (new cluster only)

Wait for the controller and load the Cloudflare credentials:

```bash
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
source ~/.config/lichnovsky/cloudflare.env
```

Then run `scripts/seal.sh <name>` for each secret:

| Name | Input | Notes |
|---|---|---|
| `cloudflare-api-token` | The cert-manager token from step 1 | |
| `cloudflared-token` | None | The script reads it from `tofu output`. |
| `grafana-admin` | None | Shows the password one time. Keep it. |
| `alertmanager-notify` | The Discord webhook URL | The script refuses a URL that is not a Discord webhook. |
| `argocd-notifications` | The same Discord webhook URL | |
| `tailscale-operator-oauth` | The OAuth client ID and secret from step 1 | |
| `vaultwarden` | An argon2 hash of the admin page password | Make the hash with `kubectl run vw-hash --rm -it --restart=Never --image=vaultwarden/server:1.37.3 -- /vaultwarden hash` |
| `papra` | None | |
| `media` | None | API keys for Sonarr, Radarr and Prowlarr, and the qBittorrent password. Shows the qBittorrent login one time. Keep it. |
| `backups` | None | Shows the **restic password** one time. Keep it in the password manager and on paper. The script refuses to run if backup secrets exist. |

The values do not go to the disk or to a command line. They go to `kubeseal` through stdin. Commit
the `sealed-*.yaml` files and push. Argo CD applies them in approximately 3 minutes.

### After the first sync

1. **Back up the Sealed Secrets key** into the password manager, then delete the file. The key
   changes each 30 days, and the controller keeps the old keys. Thus, do this again from time to
   time:
   ```bash
   (umask 077; kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
     -o yaml > ~/sealed-secrets-key.backup.yaml)
   ```
2. **Argo CD admin password:**
   1. Run `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`.
   2. Log in at `https://argocd.lichnovsky.eu`. Change the password under *User Info*.
   3. Run `kubectl -n argocd delete secret argocd-initial-admin-secret`.

## 7. LAN and remote access

### AdGuard Home

1. Open `http://192.168.50.244:3000` for the setup wizard. Set the web interface to *all
   interfaces, port 3000*. Set the DNS server to *all interfaces, port 53*. Ports 80 and 443 belong
   to Traefik. Make the admin account.
2. **Filters → DNS rewrites:** Add `lichnovsky.eu` → `192.168.50.244` and `*.lichnovsky.eu` →
   `192.168.50.244`. If a subdomain moves to a different server, add a more specific rewrite for
   it.
3. **Settings → DNS settings → Upstream DNS servers:** Use DoH, for example
   `https://dns.quad9.net/dns-query` and `https://cloudflare-dns.com/dns-query`. Select *Parallel
   requests*. Keep the cache on.
4. **Test AdGuard directly**, before you change the DNS for the house:
   ```bash
   dig +short @192.168.50.244 tv.lichnovsky.eu      # 192.168.50.244
   dig +short @192.168.50.244 github.com            # a public address
   dig +short @192.168.50.244 doubleclick.net       # 0.0.0.0 (blocked)
   ```
5. **Router → DHCP → DNS servers:** Set `192.168.50.244` first and `9.9.9.9` second. The second
   server keeps the house online when the Pi restarts. It has no ad blocking, and clients can also
   use it at other times. Thus, some ads can get through. On ASUS, set *Advertise router's IP in
   addition to user-specified DNS* to **No**.

   Do not change the WAN DNS of the router. If the router used the Pi, the router could not resolve
   names while the Pi is down.
6. Change kubectl to the name:
   `kubectl config set-cluster lichnovsky --server=https://k8s.lichnovsky.eu:6443`. The name
   resolves only through AdGuard and Tailscale. It continues to work if the IP address of the Pi
   changes.

### Tailscale

1. After the operator syncs, the admin console shows `lichnovsky-k8s-operator` and
   `lichnovsky-lan`. The route `192.168.50.244/32` is already approved.
2. Go to **DNS → Nameservers → Add nameserver → Custom**. Enter `192.168.50.244`. Enable
   **Restrict to domain** and enter `lichnovsky.eu`. This is split DNS: only these names go to
   AdGuard.
3. **Clients:** Phones accept routes automatically. Linux ignores routes by default. On Linux, run
   `sudo tailscale set --accept-routes`.
4. **Test from a phone on mobile data** (Wi-Fi off). Open `https://dns.lichnovsky.eu`. This name has
   no public record. If the page opens, remote access works from end to end.

## 8. First run of each app

Do these steps immediately after the first deployment. The first person who opens a new app becomes
its admin. On the LAN, nothing protects a new app.

**Vaultwarden** (`https://vault.lichnovsky.eu`)

1. Open `/admin`. On the internet, Cloudflare Access asks for a login first. Then enter the admin
   page password (its hash is sealed).
2. Push *Users → Invite user* and enter your e-mail. There is no SMTP, thus no e-mail goes out.
   Register at `https://vault.lichnovsky.eu` with that address.
3. Select the **master password**. It encrypts the vault, and **nobody can reset it**. Write it down
   and keep it offline. Turn on two-step login. Keep the recovery code with the master password.
4. Clients: In the Bitwarden apps and browser extension, select *self-hosted* and enter
   `https://vault.lichnovsky.eu`.

**Papra** (`https://papra.lichnovsky.eu`)

The manifest closes the registration. On a new installation (no restored data):

1. In `apps/papra/papra.yaml`, set `AUTH_IS_REGISTRATION_ENABLED` to `"true"` and push.
2. Make the first account. It becomes the owner.
3. Set the value to `"false"` again and push.

**Uptime Kuma** (`https://status.lichnovsky.eu`)

1. The first screen makes the admin account.
2. Add monitors: one HTTP monitor for each app URL, and one DNS monitor against `192.168.50.244`
   for AdGuard.
3. Go to Settings → Notifications → Discord. Use the same webhook URL. Attach the notification to
   all monitors.
4. Go to **Status Pages → New status page** and use the slug **`home`**. The page is public at
   `https://status.lichnovsky.eu/status/home`. The status widget of the website reads this page.
   The page shows only the monitors that you add to it.

**Grafana** (`https://grafana.lichnovsky.eu`)

1. Run `kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d`.
2. Log in as `admin`. Change the password under *Profile*.

The *Homelab* folder has the dashboards for the tunnel, Traefik, Argo CD and the logs.
*Node Exporter / Nodes* shows the Pi itself.

**Jellyfin** (`https://tv.lichnovsky.eu`, home and Tailscale only)

1. In the wizard, make the admin account. Keep *Allow remote connections* **on**. All traffic comes
   through Traefik, thus Jellyfin cannot see the difference between local and remote. The private
   hostname is the protection. Set *automatic port mapping* **off**.
2. Go to Dashboard → Playback. Set hardware acceleration **off**, because the Pi 5 has no video
   encoder. Set a high *Internet streaming bitrate limit*. Then remote clients do not transcode
   because of the bitrate.
3. Add the libraries: Movies → `/media/movies`, Shows → `/media/shows`, Music → `/media/music`.
   - Turn on real-time monitoring.
   - Turn **off** *Save artwork into media folders* and *Save metadata as NFO*, because the media
     is mounted read-only.
   - Turn **off** chapter image extraction and trickplay. They decode each full video, which takes
     hours of CPU for each movie.
   - Keep *Prefer embedded titles* off.
4. Use this media layout:
   ```
   movies/Title (Year)/Title (Year).mkv
   movies/Title (Year)/Title (Year).cs.srt
   shows/Series (Year)/Season 01/Series S01E01.mkv
   ```
   To copy a file:
   ```bash
   rsync -ah --mkpath --info=progress2 file.mkv "rpi:/srv/media/movies/Title (Year)/Title (Year).mkv"
   ```
   First, examine the codecs with `ffprobe`. H.264/AAC plays on all devices. HEVC 10-bit plays in
   the Jellyfin apps, but not in many browsers. In a browser, HEVC causes a CPU transcode, and the
   Pi can do approximately one 1080p stream.

**Media stack** (home and Tailscale only)

Do these steps in this sequence. The address of each app is in the [README](../README.md). In the
cluster, the apps connect to each other by short name (for example `http://sonarr`, port 80). Use
these short names in the forms below.

1. **Sonarr, Radarr, Prowlarr:** Open each app. The first screen asks for an authentication
   method. Select *Forms (Login Page)* and *Required: Enabled*. Enter a username and password, and
   keep them.
2. **Configarr:** Run Configarr one time. Do not wait for :17. Make sure that it ends without
   errors:
   ```bash
   kubectl -n tv create job --from=cronjob/configarr configarr-now
   kubectl -n tv logs -f job/configarr-now
   ```
   Then Sonarr and Radarr have the profiles *1080p* and *4K, else 1080p*, the root folder, and
   qBittorrent as download client (*Settings → Download Clients → Test* is green). Prowlarr shows
   Sonarr and Radarr under *Settings → Apps*.
3. **Prowlarr → Indexers → Add Indexer:** Add the indexers that you use. Push *Test* for each one.
   If an indexer is behind a Cloudflare check, give it the tag `flaresolverr`. Push *Sync App
   Indexers*, or wait some minutes. The indexers then show in Sonarr and Radarr under *Settings →
   Indexers*.
4. **qBittorrent:** Log in as `admin` with the password that `seal.sh media` showed. Do not change
   settings. The downloads go to `/media/downloads`. Seeding stops at ratio 1 or after 24 hours.
5. **Bazarr:** Make the login (*Settings → General → Security → Forms*). Then:
   - *Settings → Languages:* Make a profile, for example Czech + English. Set it as the default for
     series and movies.
   - *Settings → Providers:* Add OpenSubtitles.com (free account) and Podnapisi. Titulky.com is
     good for Czech, but it needs a VIP membership.
   - *Settings → Library → Sonarr:* Select *Enabled*. Enter address `sonarr`, port `80` and the API
     key from Sonarr (*Settings → General*). On the *Radarr* tab, enter `radarr`, `80` and the key
     from Radarr. Do not add path mappings, because the paths are the same in all apps.
   - *Settings → Integrations → Jellyfin:* Select *Enabled*. Enter the server URL `http://jellyfin`
     and an API key from Jellyfin (*Dashboard → API Keys*). Set the refresh to *Immediate*. Select
     the two libraries and their refresh check boxes. Then new subtitles show in Jellyfin
     immediately.
6. **Seerr** (`https://watchlist.lichnovsky.eu`):
   1. Select *Jellyfin*. Sign in with the Jellyfin admin account. Enter the Jellyfin URL
      `http://jellyfin`, port `80`, and the external URL `https://tv.lichnovsky.eu`.
   2. Sync the libraries (Movies, Shows).
   3. Add the *Radarr server*: `radarr`, port `80`, the API key of Radarr, profile *1080p*, root
      folder `/media/movies`, external URL `https://radarr.lichnovsky.eu`. Set *Default server* on.
   4. Add the *Sonarr server*: `sonarr`, port `80`, the API key of Sonarr, profile *1080p*, root
      folder `/media/shows`, external URL `https://sonarr.lichnovsky.eu`. Set *Default server* and
      season folders on.
   5. Under *Settings → General*, set the *Application URL* to `https://watchlist.lichnovsky.eu`.
   6. Family members sign in with their Jellyfin accounts. If their requests must not wait for you,
      give them *Auto-Approve* under *Users*.
7. **Optional:**
   - **Discord:** In Sonarr and Radarr, use *Settings → Connect → Discord*. In Seerr, use *Settings →
     Notifications → Discord*. Use the alerts webhook.
   - **Router:** Forward port `50413` TCP+UDP to `192.168.50.244` for incoming peers. This gives
     faster downloads from more sources. It works only with a public IPv4 address. Behind CGNAT (the
     WAN IP of the router is `10.x` or `100.64.x`), a port forward cannot work. A VPN with port
     forwarding solves this ([operations.md](operations.md#media-stack)).
   - **Uptime Kuma:** The names of the stack are private. Thus, the monitors must use the URLs in
     the cluster, for example `http://seerr.tv.svc.cluster.local/api/v1/status` and
     `http://sonarr.tv.svc.cluster.local/ping`.

To test the stack, request a movie in Seerr. The movie shows in Radarr, then in qBittorrent, and
after the download in Jellyfin. Bazarr adds subtitles, usually in less than one hour.

You set up **AdGuard Home** in step 7.

## 9. Final checks

```bash
kubectl -n argocd get applications              # all Synced / Healthy
kubectl get certificate -A                      # wildcard-lichnovsky-eu Ready
curl -sI https://lichnovsky.eu | head -1        # HTTP/2 200
```

- A test alert gets to Discord ([operations.md → Alerts](operations.md#alerts)).
- On the next morning, each backup has a new snapshot. A restore test is on the calendar
  ([operations.md → Backups](operations.md#backups)).
- The password manager has: the Cloudflare credentials file, the deploy key, the Sealed Secrets
  key, the k3s server token, the restic password, and the Grafana and Argo CD passwords.
- On paper, you have: the Vaultwarden master password with its recovery code, and the restic
  password.
