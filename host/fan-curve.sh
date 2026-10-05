#!/usr/bin/env bash
# Quieter fan curve for the Pi 5. In a case, the default curve (on at 50 °C, off below 45 °C) never
# stops the fan, and the 60 °C step jumps it to ~4,800 RPM at every peak. The Pi throttles at 80 °C.
# Idempotent: safe to run again. Run as root:  sudo bash fan-curve.sh
# The trip temperatures change immediately; the speeds only after a reboot (they come from config.txt).
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

# One entry per fan level: on at TEMPS °C, off 5 °C lower, PWM speed 0-255.
TEMPS=(55 65 70 75)
SPEEDS=(50 90 150 255)

CONFIG=/boot/firmware/config.txt
cp -n "$CONFIG" "$CONFIG.bak-before-fan"
sed -i '/^# BEGIN homelab fan curve/,/^# END homelab fan curve/d' "$CONFIG"
{
  echo "# BEGIN homelab fan curve (host/fan-curve.sh)"
  echo "[all]"
  for i in 0 1 2 3; do
    echo "dtparam=fan_temp${i}=${TEMPS[i]}000,fan_temp${i}_hyst=5000,fan_temp${i}_speed=${SPEEDS[i]}"
  done
  echo "# END homelab fan curve"
} >> "$CONFIG"
sed -n '/^# BEGIN homelab fan curve/,/^# END homelab fan curve/p' "$CONFIG"

# Apply the temperatures now. Trip 0 is the 110 °C critical trip; 1-4 are the fan levels.
# Written low to high, so the trips stay in ascending order at every step.
for i in 0 1 2 3; do
  echo "${TEMPS[i]}000" > "/sys/class/thermal/thermal_zone0/trip_point_$((i + 1))_temp"
done
grep -H . /sys/class/thermal/thermal_zone0/trip_point_[1-4]_temp
echo "Trip temperatures active now. Reboot to apply the speeds:  sudo reboot"
