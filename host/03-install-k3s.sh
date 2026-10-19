#!/usr/bin/env bash
# Install k3s with this folder's config, or upgrade it: bump K3S_VERSION and run again.
# Idempotent: safe to run again. Run as root:  sudo bash 03-install-k3s.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
step() { printf '\n== %s\n' "$*"; }

K3S_VERSION=v1.37.1+k3s1
NODE=$(sed -n 's/^node-name: *//p' "$HERE/k3s-config.yaml")

step "1/4 preflight"
grep -qw memory /sys/fs/cgroup/cgroup.controllers ||
  { echo "ERROR: memory cgroup not active; run 02-setup-pi.sh and reboot first"; exit 1; }
findmnt -n /srv/backup >/dev/null ||
  { echo "ERROR: /srv/backup not mounted; etcd snapshots go there"; exit 1; }
[[ $(hostname) == "$NODE" ]] ||
  { echo "ERROR: hostname is $(hostname), config says $NODE; run 01-set-hostname.sh first"; exit 1; }
echo "ok"

step "2/4 config"
changed=false
install_if_changed() {   # <source> <destination> <mode>
  cmp -s "$1" "$2" && return
  install -D -m "$3" "$1" "$2"; changed=true; echo "wrote $2"
}
install_if_changed "$HERE/k3s-config.yaml" /etc/rancher/k3s/config.yaml 0600
# Before the install, so k3s starts with the Go heap cap from the first boot.
install_if_changed "$HERE/k3s-memory.conf" /etc/systemd/system/k3s.service.d/memory.conf 0644
$changed || echo "unchanged"

step "3/4 k3s $K3S_VERSION"
installed=$(k3s --version 2>/dev/null | awk 'NR==1 {print $3}' || true)
if [[ $installed == "$K3S_VERSION" ]]; then
  echo "already installed"
  if $changed; then systemctl daemon-reload; systemctl restart k3s; echo "restarted for the new config"; fi
else
  if [[ -n $installed ]]; then
    echo "upgrading from $installed; etcd snapshot first"
    k3s etcd-snapshot save --name "pre-$K3S_VERSION"
  fi
  curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
  INSTALL_K3S_VERSION=$K3S_VERSION sh /tmp/k3s-install.sh
  rm -f /tmp/k3s-install.sh
fi

step "4/4 wait for node $NODE"
for _ in {1..90}; do k3s kubectl get node "$NODE" >/dev/null 2>&1 && break; sleep 2; done
k3s kubectl wait --for=condition=Ready "node/$NODE" --timeout=180s
k3s kubectl get node -o wide

printf '\nDone. Save the server token in your password manager (restoring etcd needs it):\n'
printf '  sudo cat /var/lib/rancher/k3s/server/token\n'
