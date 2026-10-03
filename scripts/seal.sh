#!/usr/bin/env bash
# Create one SealedSecret. Plaintext never touches disk or a command line (`ps`): only stdin.
# Usage: scripts/seal.sh <secret>     (needs kubeseal, openssl and cluster access)
set -euo pipefail
cd "$(dirname "$0")/.."

ask()  { local v; read -rsp "$1: " v; echo >&2; [[ -n $v ]] || { echo "empty, aborted" >&2; exit 1; }; printf %s "$v"; }
rand() { openssl rand -hex 24; }
discord() {
  local url; url=$(ask 'Discord webhook URL')
  [[ $url == https://discord.com/api/webhooks/* ]] ||
    { echo "that doesn't look like a Discord webhook URL (it must start with https://discord.com/api/webhooks/)" >&2; exit 1; }
  printf %s "$url"
}

# seal <file> <namespace> <name> key=value...
seal() {
  local file=$1 ns=$2 name=$3 kv sealed; shift 3
  # Into a variable first: a failing kubeseal must not truncate an existing file.
  sealed=$({
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ndata:\n' "$name" "$ns"
    for kv in "$@"; do
      printf '  %s: %s\n' "${kv%%=*}" "$(printf %s "${kv#*=}" | openssl base64 -A)"
    done
  } | kubeseal --format yaml)
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$sealed" > "$file"
  echo "sealed $ns/$name -> $file"
}

case ${1:-} in
  cloudflare-api-token)  # Cloudflare -> API Tokens -> template "Edit zone DNS", zone lichnovsky.eu
    token=$(ask 'Cloudflare DNS token for cert-manager')
    seal platform/cluster/secrets/sealed-cloudflare-api-token.yaml cert-manager cloudflare-api-token "api-token=$token" ;;

  cloudflared-token)     # from OpenTofu; source ~/.config/lichnovsky/cloudflare.env first
    token=$(tofu -chdir=cloudflare output -raw tunnel_token)
    seal platform/cloudflared/sealed-cloudflared-token.yaml networking cloudflared-token "token=$token" ;;

  grafana-admin)
    pw=$(rand)
    seal platform/cluster/secrets/sealed-grafana-admin.yaml monitoring grafana-admin admin-user=admin "admin-password=$pw"
    echo "Grafana login: admin / $pw   (save it)" ;;

  alertmanager-notify)   # Discord: channel -> Edit Channel -> Integrations -> Webhooks -> copy URL
    url=$(discord)
    seal platform/cluster/secrets/sealed-alertmanager-notify.yaml monitoring alertmanager-notify "discord-webhook-url=$url" ;;

  argocd-notifications)  # same Discord webhook as alertmanager-notify
    url=$(discord)
    seal platform/cluster/secrets/sealed-argocd-notifications.yaml argocd argocd-notifications-secret "discord-webhook-url=$url" ;;

  tailscale-operator-oauth)  # Tailscale OAuth client, see https://tailscale.com/kb/1236/kubernetes-operator
    id=$(ask 'Tailscale OAuth client ID'); secret=$(ask 'Tailscale OAuth client secret')
    seal platform/cluster/secrets/sealed-tailscale-operator-oauth.yaml tailscale operator-oauth "client_id=$id" "client_secret=$secret" ;;

  vaultwarden)           # argon2 hash: kubectl run vw-hash --rm -it --restart=Never --image=vaultwarden/server:1.37.3 -- /vaultwarden hash
    token=$(ask 'Vaultwarden ADMIN_TOKEN (argon2 hash)')
    seal apps/vaultwarden/sealed-vaultwarden.yaml vaultwarden vaultwarden "ADMIN_TOKEN=$token" ;;

  papra)
    seal apps/papra/sealed-papra.yaml papra papra "AUTH_SECRET=$(openssl rand -hex 48)" ;;

  media)                 # API keys for Sonarr/Radarr/Prowlarr + qBittorrent's Web UI password (and its hash)
    [[ -e apps/media/sealed-media.yaml ]] &&
      { echo "media secret exists; new keys would break Bazarr/Seerr and qBittorrent keeps its old password" >&2; exit 1; }
    qbt=$(rand)
    # qBittorrent's format: PBKDF2-HMAC-SHA512, 100000 rounds, 16-byte salt -> "salt:key" in base64
    hash=$(printf %s "$qbt" | python3 -c 'import base64,hashlib,os,sys
salt=os.urandom(16); key=hashlib.pbkdf2_hmac("sha512", sys.stdin.buffer.read(), salt, 100000)
print(base64.b64encode(salt).decode() + ":" + base64.b64encode(key).decode())')
    seal apps/media/sealed-media.yaml tv media \
      "SONARR_API_KEY=$(openssl rand -hex 16)" "RADARR_API_KEY=$(openssl rand -hex 16)" \
      "PROWLARR_API_KEY=$(openssl rand -hex 16)" \
      "QBITTORRENT_PASSWORD=$qbt" "QBITTORRENT_PASSWORD_PBKDF2=$hash"
    echo "qBittorrent login: admin / $qbt   (save it)" ;;

  share)                 # R2 -> Manage API tokens -> Object Read & Write, only bucket lichnovsky-share
    id=$(ask 'R2 Access Key ID'); secret=$(ask 'R2 Secret Access Key')
    seal apps/share/sealed-gokapi-r2.yaml share gokapi-r2 "access-key-id=$id" "secret-access-key=$secret" ;;

  backups)               # one restic password + a rest-server login per namespace, generated together
    [[ -e platform/backups/secrets/sealed-rest-server-htpasswd.yaml ]] &&
      { echo "backup secrets exist; re-generating would lock you out of existing backups" >&2; exit 1; }
    restic=$(rand); htpasswd=""
    for ns in vaultwarden papra photos monitoring dns tv; do
      pw=$(rand)
      seal "platform/backups/secrets/sealed-k8up-repo-$ns.yaml" "$ns" k8up-repo \
        "RESTIC_PASSWORD=$restic" "REST_USER=$ns" "REST_PASSWORD=$pw"
      htpasswd+="$ns:{SHA}$(printf %s "$pw" | openssl dgst -sha1 -binary | openssl base64)"$'\n'
    done
    seal platform/backups/secrets/sealed-rest-server-htpasswd.yaml backups rest-server-htpasswd "htpasswd=$htpasswd"
    echo "RESTIC PASSWORD: $restic   (save it in your password manager AND offline)" ;;

  backup-namespace)      # give one more namespace a backup login, keeping the existing ones
    ns=${2:?usage: $0 backup-namespace <namespace>}
    [[ -e platform/backups/secrets/sealed-k8up-repo-$ns.yaml ]] &&
      { echo "$ns already has backup credentials" >&2; exit 1; }
    # Same restic password as every other namespace, and the current logins, read from the cluster.
    restic=$(kubectl -n vaultwarden get secret k8up-repo -o jsonpath='{.data.RESTIC_PASSWORD}' | openssl base64 -d -A)
    htpasswd=$(kubectl -n backups get secret rest-server-htpasswd -o jsonpath='{.data.htpasswd}' | openssl base64 -d -A)
    [[ -n $restic && -n $htpasswd ]] || { echo "couldn't read the backup secrets from the cluster" >&2; exit 1; }
    pw=$(rand)
    seal "platform/backups/secrets/sealed-k8up-repo-$ns.yaml" "$ns" k8up-repo \
      "RESTIC_PASSWORD=$restic" "REST_USER=$ns" "REST_PASSWORD=$pw"
    htpasswd+=$'\n'"$ns:{SHA}$(printf %s "$pw" | openssl dgst -sha1 -binary | openssl base64)"$'\n'
    seal platform/backups/secrets/sealed-rest-server-htpasswd.yaml backups rest-server-htpasswd "htpasswd=$htpasswd"
    echo "now add a Schedule for $ns (platform/backups/schedules.yaml) and allow it in rest-server's NetworkPolicy" ;;

  *) echo "usage: $0 {cloudflare-api-token|cloudflared-token|grafana-admin|alertmanager-notify|argocd-notifications|tailscale-operator-oauth|vaultwarden|papra|media|share|backups|backup-namespace <ns>}" >&2
     exit 1 ;;
esac
