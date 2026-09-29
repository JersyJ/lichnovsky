#!/usr/bin/env bash
# Create one SealedSecret. Plaintext never touches the disk and never appears in a command line
# (so not in `ps`): the Secret is built with bash built-ins and reaches base64/kubeseal only via stdin.
# Usage: scripts/seal.sh <secret>     (needs kubeseal, openssl and access to the cluster)
set -euo pipefail
cd "$(dirname "$0")/.."

ask()  { local v; read -rsp "$1: " v; echo >&2; [[ -n $v ]] || { echo "empty, aborted" >&2; exit 1; }; printf %s "$v"; }
rand() { openssl rand -hex 24; }

# seal <file> <namespace> <name> key=value...
seal() {
  local file=$1 ns=$2 name=$3 kv; shift 3
  mkdir -p "$(dirname "$file")"
  {
    printf 'apiVersion: v1\nkind: Secret\nmetadata:\n  name: %s\n  namespace: %s\ndata:\n' "$name" "$ns"
    for kv in "$@"; do
      printf '  %s: %s\n' "${kv%%=*}" "$(printf %s "${kv#*=}" | openssl base64 -A)"
    done
  } | kubeseal --format yaml > "$file"
  echo "sealed $ns/$name -> $file"
}

case ${1:-} in
  cloudflare-api-token)  # Cloudflare -> API Tokens -> template "Edit zone DNS", zone lichnovsky.eu
    seal platform/cluster/secrets/sealed-cloudflare-api-token.yaml cert-manager cloudflare-api-token \
      "api-token=$(ask 'Cloudflare DNS token for cert-manager')" ;;

  cloudflared-token)     # from OpenTofu; source ~/.config/lichnovsky/cloudflare.env first
    seal platform/cloudflared/sealed-cloudflared-token.yaml networking cloudflared-token \
      "token=$(tofu -chdir=cloudflare output -raw tunnel_token)" ;;

  grafana-admin)
    pw=$(rand)
    seal platform/cluster/secrets/sealed-grafana-admin.yaml monitoring grafana-admin admin-user=admin "admin-password=$pw"
    echo "Grafana login: admin / $pw   (save it)" ;;

  alertmanager-notify)   # Discord: channel -> Edit Channel -> Integrations -> Webhooks -> copy URL
    url=$(ask 'Discord webhook URL')
    [[ $url == https://discord.com/api/webhooks/* ]] ||
      { echo "that doesn't look like a Discord webhook URL (it must start with https://discord.com/api/webhooks/)" >&2; exit 1; }
    seal platform/cluster/secrets/sealed-alertmanager-notify.yaml monitoring alertmanager-notify "discord-webhook-url=$url" ;;

  tailscale-operator-oauth)  # Tailscale OAuth client, see https://tailscale.com/kb/1236/kubernetes-operator
    seal platform/cluster/secrets/sealed-tailscale-operator-oauth.yaml tailscale operator-oauth \
      "client_id=$(ask 'Tailscale OAuth client ID')" "client_secret=$(ask 'Tailscale OAuth client secret')" ;;

  vaultwarden)           # argon2 hash: kubectl run vw-hash --rm -it --restart=Never --image=vaultwarden/server:1.37.3 -- /vaultwarden hash
    seal apps/vaultwarden/sealed-vaultwarden.yaml vaultwarden vaultwarden "ADMIN_TOKEN=$(ask 'Vaultwarden ADMIN_TOKEN (argon2 hash)')" ;;

  papra)
    seal apps/papra/sealed-papra.yaml papra papra "AUTH_SECRET=$(openssl rand -hex 48)" ;;

  backups)               # one restic password + a rest-server login per namespace, generated together
    [[ -e platform/backups/secrets/sealed-rest-server-htpasswd.yaml ]] &&
      { echo "backup secrets exist; re-generating would lock you out of existing backups" >&2; exit 1; }
    restic=$(rand); htpasswd=""
    for ns in vaultwarden papra photos monitoring dns; do
      pw=$(rand)
      seal "platform/backups/secrets/sealed-k8up-repo-$ns.yaml" "$ns" k8up-repo \
        "RESTIC_PASSWORD=$restic" "REST_USER=$ns" "REST_PASSWORD=$pw"
      htpasswd+="$ns:{SHA}$(printf %s "$pw" | openssl dgst -sha1 -binary | openssl base64)"$'\n'
    done
    seal platform/backups/secrets/sealed-rest-server-htpasswd.yaml backups rest-server-htpasswd "htpasswd=$htpasswd"
    echo "RESTIC PASSWORD: $restic   (save it in your password manager AND offline)" ;;

  *) echo "usage: $0 {cloudflare-api-token|cloudflared-token|grafana-admin|alertmanager-notify|tailscale-operator-oauth|vaultwarden|papra|backups}" >&2
     exit 1 ;;
esac
