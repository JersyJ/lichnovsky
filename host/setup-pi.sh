#!/usr/bin/env bash
# Phase 1 host preparation for rpi-01 (Raspberry Pi OS Trixie, booted from NVMe).
# Idempotent: safe to run again. Run as root:  sudo bash setup-pi.sh
# Reboot afterwards (the memory cgroup only takes effect after a reboot).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
step() { printf '\n== %s\n' "$*"; }

step "1/7 memory cgroup (Pi firmware disables it by default; k3s needs it to enforce limits)"
CMDLINE=/boot/firmware/cmdline.txt
if grep -q 'cgroup_enable=memory' "$CMDLINE"; then
  echo "already set"
else
  cp -n "$CMDLINE" "$CMDLINE.bak-before-k3s"
  sed -i '1 s/$/ cgroup_memory=1 cgroup_enable=memory/' "$CMDLINE"   # must stay ONE line
  echo "added. Takes effect after reboot"
fi
cat "$CMDLINE"

step "2/7 packages: security updates + tools"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq unattended-upgrades parted smartmontools nvme-cli jq >/dev/null
echo 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true' | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades
echo "unattended-upgrades enabled"

step "3/7 firmware (EEPROM) update"
rpi-eeprom-update -a || true   # stages a newer bootloader if there is one; applied on reboot

step "4/7 journald size cap (1 GB, 1 month)"
install -D -m 0644 "$HERE/journald-homelab.conf" /etc/systemd/journald.conf.d/homelab.conf
systemctl restart systemd-journald
echo "journal capped at 1 GB / 1 month"

step "5/7 Wi-Fi power saving off (stops latency spikes and dropped connections on a server)"
install -D -m 0644 /dev/stdin /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf <<'EOF'
[connection]
# 2 = disable
wifi.powersave = 2
EOF
echo "written. Takes effect after reboot"

step "6/7 backup disk: SD card -> ext4 'backup' at /srv/backup"
DEV=/dev/mmcblk0
if blkid -L backup >/dev/null 2>&1; then
  echo "a filesystem labelled 'backup' already exists: $(blkid -L backup); not formatting"
else
  # Safety checks: must be the SD card, not the boot/root disk, not mounted, ~119 GB.
  [[ -b $DEV ]] || { echo "ERROR: $DEV not found"; exit 1; }
  findmnt -n -o SOURCE / | grep -q nvme0n1 || { echo "ERROR: root is not on NVMe, refusing"; exit 1; }
  if lsblk -n -o MOUNTPOINTS "$DEV" | grep -q .; then echo "ERROR: $DEV is mounted, refusing"; exit 1; fi
  size_gb=$(( $(blockdev --getsize64 "$DEV") / 1000000000 ))
  (( size_gb > 100 && size_gb < 140 )) || { echo "ERROR: $DEV is ${size_gb} GB, expected ~128 GB, refusing"; exit 1; }
  echo "formatting $DEV (${size_gb} GB)"
  wipefs -a "$DEV"
  parted -s "$DEV" mklabel gpt mkpart backup ext4 0% 100%
  udevadm settle
  mkfs.ext4 -q -F -L backup "${DEV}p1"
fi
mkdir -p /srv/backup
if ! findmnt -n /srv/backup >/dev/null; then
  chattr +i /srv/backup   # empty mount point is immutable: if the card is missing, writes FAIL
fi
grep -q 'LABEL=backup' /etc/fstab || \
  echo 'LABEL=backup /srv/backup ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2' >> /etc/fstab
systemctl daemon-reload
findmnt -n /srv/backup >/dev/null || mount /srv/backup
mkdir -p /srv/backup/restic /srv/backup/etcd
chown 1000:1000 /srv/backup/restic   # the rest-server pod runs as UID 1000
chmod 700 /srv/backup/etcd
df -h /srv/backup

step "7/7 media folder for Jellyfin (on the NVMe)"
mkdir -p /srv/media
echo "/srv/media ready"

printf '\nDone. Now reboot:  sudo reboot\n'
