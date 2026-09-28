#!/usr/bin/env bash
# Secrets workflow for this repo (Sealed Secrets).
#
#   scripts/secrets.sh init    Render every template into .secrets/ (git-ignored), filling in
#                              random values and prompting for the ones you have to paste.
#   scripts/secrets.sh seal    Encrypt every .secrets/*.yaml with the cluster's public key into
#                              the app folder that uses it. Only these SealedSecrets get committed.
#
# Needs: kubeseal (github.com/bitnami/sealed-secrets), openssl, and a kubeconfig that reaches the
# cluster (sealed-secrets-controller in kube-system). A SealedSecret only decrypts in the cluster
# that sealed it: back up the controller key (docs/guide.md, "Disaster recovery").
set -euo pipefail
cd "$(dirname "$0")/.."

TPL=scripts/secret-templates
OUT=.secrets
BACKUP_NAMESPACES=(security documents photos monitoring dns)

# secret file in .secrets/  ->  folder where its SealedSecret lives
declare -A DEST=(
  [cloudflared-token]=apps/networking/cloudflared
  [vaultwarden]=apps/security/vaultwarden
  [papra]=apps/documents/papra
  [cloudflare-api-token]=apps/platform/secrets
  [grafana-admin]=apps/platform/secrets
  [alertmanager-notify]=apps/platform/secrets
  [tailscale-operator-oauth]=apps/platform/secrets
)
for ns in "${BACKUP_NAMESPACES[@]}"; do DEST[k8up-repo-$ns]=apps/backups/secrets; done
DEST[rest-server-htpasswd]=apps/backups/secrets

ask() { local prompt=$1 v; read -r -s -p "$prompt: " v; echo >&2; printf '%s' "$v"; }

fill() { # fill <file>: replace placeholders in place
  local f=$1
  while grep -q '__RANDOM_HEX_48__' "$f"; do
    sed -i "0,/__RANDOM_HEX_48__/s//$(openssl rand -hex 48)/" "$f"; done
  while grep -q '__RANDOM_B64_24__' "$f"; do
    sed -i "0,/__RANDOM_B64_24__/s//$(openssl rand -base64 24 | tr -d '/+=')/" "$f"; done
  while grep -q '__ASK__' "$f"; do
    local key; key=$(grep -m1 '__ASK__' "$f" | sed 's/:.*//; s/^ *//')
    local v; v=$(ask "$(basename "$f" .yaml) -> $key")
    python3 - "$f" "$v" <<'PY'
import sys
p,v=sys.argv[1],sys.argv[2]
s=open(p).read()
# the template quotes each placeholder, so escape for its quoting style
i=s.index("__ASK__"); q=s[i-1]
v=v.replace("'", "''") if q=="'" else v.replace("\\","\\\\").replace('"','\\"')
open(p,"w").write(s.replace("__ASK__",v,1))
PY
  done
}

cmd_init() {
  mkdir -p "$OUT"
  for t in "$TPL"/*.yaml; do
    local name; name=$(basename "$t" .yaml)
    [[ $name == k8up-repo ]] && continue
    [[ -e $OUT/$name.yaml ]] && { echo "keep   $OUT/$name.yaml"; continue; }
    cp "$t" "$OUT/$name.yaml"
    # The tunnel token comes straight from OpenTofu when infra/cloudflare has been applied.
    if [[ $name == cloudflared-token ]] && command -v tofu >/dev/null \
       && tok=$(tofu -chdir=infra/cloudflare output -raw tunnel_token 2>/dev/null) && [[ -n $tok ]]; then
      sed -i "s|__ASK__|$tok|" "$OUT/$name.yaml"; echo "(tunnel token taken from OpenTofu output)"
    fi
    fill "$OUT/$name.yaml"; echo "wrote  $OUT/$name.yaml"
  done

  # One restic password for every backed-up namespace, plus a rest-server login per namespace.
  if [[ ! -e $OUT/k8up-repo-${BACKUP_NAMESPACES[0]}.yaml ]]; then
    local restic htpasswd=""; restic=$(openssl rand -base64 32 | tr -d '/+=')
    for ns in "${BACKUP_NAMESPACES[@]}"; do
      local restpw; restpw=$(openssl rand -hex 24)
      sed "s|__NAMESPACE__|$ns|g; s|__RESTIC_PASSWORD__|$restic|; s|__REST_PASSWORD__|$restpw|" \
        "$TPL/k8up-repo.yaml" > "$OUT/k8up-repo-$ns.yaml"
      # rest-server accepts "{SHA}" entries: base64(sha1(password)). Fine for long random passwords.
      htpasswd+="    $ns:{SHA}$(printf '%s' "$restpw" | openssl dgst -sha1 -binary | openssl base64)"$'\n'
      echo "wrote  $OUT/k8up-repo-$ns.yaml"
    done
    printf '%s\n' "apiVersion: v1" "kind: Secret" "metadata:" "  name: rest-server-htpasswd" \
      "  namespace: backups" "stringData:" "  htpasswd: |" > "$OUT/rest-server-htpasswd.yaml"
    printf '%s' "$htpasswd" >> "$OUT/rest-server-htpasswd.yaml"
    echo "wrote  $OUT/rest-server-htpasswd.yaml"
    echo
    echo "RESTIC PASSWORD (store it in your password manager AND offline): $restic"
  fi
  echo; echo "Next: review .secrets/*.yaml, then run: scripts/secrets.sh seal"
}

cmd_seal() {
  command -v kubeseal >/dev/null || { echo "kubeseal not found" >&2; exit 1; }
  for f in "$OUT"/*.yaml; do
    local name; name=$(basename "$f" .yaml)
    local dest=${DEST[$name]:-}
    [[ -z $dest ]] && { echo "skip   $f (no destination mapping in scripts/secrets.sh)"; continue; }
    grep -q '__[A-Z0-9_]*__' "$f" && { echo "ERROR  $f still has placeholders" >&2; exit 1; }
    mkdir -p "$dest"
    kubeseal --format yaml < "$f" > "$dest/sealed-$name.yaml"
    echo "sealed $f -> $dest/sealed-$name.yaml"
  done
}

case "${1:-}" in
  init) cmd_init ;;
  seal) cmd_seal ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
