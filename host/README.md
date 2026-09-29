# host/

Files that go on the Pi itself, not into Kubernetes. Run the scripts in number order, on a fresh
Raspberry Pi OS; all are safe to run again.

| File | Where it goes / what it does |
|---|---|
| `01-set-hostname.sh` | renames the Pi to `rpi-01` through cloud-init; run before k3s |
| `02-setup-pi.sh` | memory cgroup, packages, journald cap, Wi-Fi power saving off, SD card as `/srv/backup`, `/srv/media` |
| `03-install-k3s.sh` | installs k3s with the two files below and waits for the node; also upgrades it (bump `K3S_VERSION`) |
| `journald-homelab.conf` | installed by `02-setup-pi.sh` |
| `k3s-config.yaml` | `/etc/rancher/k3s/config.yaml`, installed by `03-install-k3s.sh` |
| `k3s-memory.conf` | `/etc/systemd/system/k3s.service.d/memory.conf`, installed by `03-install-k3s.sh` |

How to run them, and the checks in between: [docs/setup.md, step 3](../docs/setup.md#3-the-pi).

Changing `k3s-config.yaml` or `k3s-memory.conf` later: copy them to the Pi and run `03-install-k3s.sh`
again; it restarts k3s only if a file changed (pods keep running).
