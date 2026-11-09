# SLEEP POLICY

## Decision

**Suspend is disabled by default.** Screen turns off after inactivity, the
session locks, and the machine is powered off overnight.

This is not a preference: on this exact hardware, 14 documented attempts to make
suspend work all ended in a hard freeze or a thermal cascade
(`docs/SLEEP-WAKE-ISSUES.md` in the parent repository):

- s2idle → hard freeze ~42 s after resume, unclean btrfs
- S3/deep → KWin atomic-modeset failures, 96 °C, thermal shutdown
- `nvidia_drm.fbdev=1` → dGPU stuck at 40 W
- GSP disabled → VRAM corruption that worsens every cycle
- `mem_sleep_default=*` on the cmdline → instability in every variant

"No sleep" does not harm the hardware: CPUs/GPUs/SSDs are rated for continuous
operation, and idle power is ~15–25 W.

## What `disable` does

```bash
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
# /etc/systemd/logind.conf.d/90-nocowboy-sleep.conf
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
# powerdevil: display off after 5 min (AC) / 2 min (battery)
```

## Test sleep (opt-in)

```bash
sudo /root/FedoraKDE/scripts/sleep-policy.sh enable
sudo systemctl suspend
# watch for 2 minutes:
watch -n5 'sensors | grep -E "Package|fan"; nvidia-smi --query-gpu=power.draw --format=csv,noheader'
```

`enable` also installs `/etc/systemd/system-sleep/99-kwin-fix`, a bounded
userspace resume hook: backlight reset, DRM reprobe, KWin reconfigure via D-Bus
(5 s timeout), GPU power logged to `/var/log/kwin-sleep.log`. It never touches
kernel parameters.

If anything freezes or the temperature climbs:

```bash
sudo /root/FedoraKDE/scripts/sleep-policy.sh rollback
```

`status` prints the masked targets, `/sys/power/mem_sleep`, and whether the hook
is installed. The script refuses to run if a deprecated parameter
(`fbdev=1`, `mem_sleep_default=*`) is present in `/etc/default/grub`.
