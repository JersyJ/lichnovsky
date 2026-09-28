#!/usr/bin/env bash
# Rename the Pi through cloud-init (default: rpi-01). Run BEFORE installing k3s, then reboot.
# Usage: sudo bash set-hostname.sh [name]
#
# Raspberry Pi Imager (Trixie) sets the hostname via cloud-init (NoCloud seed in /boot/firmware).
# cloud-init re-applies `hostname:` and /etc/hosts on every boot (update_hostname and
# update_etc_hosts run "always"), but from its CACHED datasource (/var/lib/cloud/instance/obj.pkl),
# not from the seed file. So: change the seed, drop only that cache, reboot. The instance ID stays
# the same, so this is NOT a new first boot. Per-instance modules (users, passwords, SSH) don't
# run again; only the always-modules pick up the new name.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
NEW=${1:-rpi-01}
[[ $NEW =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || { echo "invalid hostname: $NEW"; exit 1; }
SEED=/boot/firmware/user-data

grep -q '^hostname:' "$SEED" || { echo "ERROR: no 'hostname:' line in $SEED"; exit 1; }
cp -n "$SEED" "$SEED.bak-before-rename"
sed -i -E "s/^hostname: .*/hostname: $NEW/" "$SEED"
echo "seed: $(grep '^hostname:' "$SEED")"

rm -f /var/lib/cloud/instance/obj.pkl
echo "cloud-init datasource cache dropped; the seed is re-read on next boot"

echo "Now reboot:  sudo reboot"
echo "Afterwards 'hostname' should print $NEW, and /etc/hosts should contain '127.0.1.1 $NEW'."
