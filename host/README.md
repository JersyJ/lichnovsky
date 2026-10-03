# host/

These files are for the Pi itself, not for Kubernetes. Run the scripts in number sequence on a new
Raspberry Pi OS. You can run each script again safely.

| File | Location / function |
|---|---|
| `01-set-hostname.sh` | Changes the Pi name to `rpi-01` through cloud-init. Run it before k3s. |
| `02-setup-pi.sh` | Memory cgroup, packages, inotify limits, journal on disk, Wi-Fi power saving off, host DNS, SD card as `/srv/backup`, `/srv/media` |
| `03-install-k3s.sh` | Installs k3s with the two files below and waits for the node. It also upgrades k3s (change `K3S_VERSION`). |
| `journald-homelab.conf` | `02-setup-pi.sh` installs it. |
| `k3s-config.yaml` | `/etc/rancher/k3s/config.yaml`. `03-install-k3s.sh` installs it. |
| `k3s-memory.conf` | `/etc/systemd/system/k3s.service.d/memory.conf`. `03-install-k3s.sh` installs it. |

For the procedure and the checks between the scripts, refer to
[docs/setup.md, step 3](../docs/setup.md#3-the-pi).

To change `k3s-config.yaml` or `k3s-memory.conf` later:

1. Copy the files to the Pi.
2. Run `03-install-k3s.sh` again.

The script restarts k3s only if a file changed. The pods continue to run.
