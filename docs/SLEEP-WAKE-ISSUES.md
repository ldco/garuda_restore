# Sleep/Wake Issues - Troubleshooting History

## Status: REVERTED TO DEFAULTS (2025-12-31)

All sleep "fixes" caused system instability (thermal reboots). Reverted to system defaults.

---

## Original Problem

- PC takes long time to wake from sleep
- Very unresponsive on wake
- Need to tap keyboard multiple times to wake

## System Configuration

### Hardware
- **Laptop**: ASUS TUF Gaming F15 FX507ZR
- **CPU**: Intel 12th Gen Alder Lake (12 cores, 20 threads)
- **GPU**: Hybrid - Intel Iris Xe + NVIDIA RTX 3070 Mobile
- **RAM**: 32GB DDR5

### The Hybrid GPU Problem

This system has **hybrid graphics** which causes sleep/wake issues on Wayland:
- Intel iGPU handles display (power efficient)
- NVIDIA dGPU for heavy tasks (115W TDP)
- KWin Wayland has bugs restoring displays after wake on hybrid GPU setups

---

## Fixes Attempted (ALL FAILED)

### Attempt 1: Deep Sleep (S3) via GRUB

**What we did:**
```bash
# Added to /etc/default/grub:
GRUB_CMDLINE_LINUX_DEFAULT='mem_sleep_default=deep quiet loglevel=3 nvidia_drm.modeset=1'
```

**Result:** System crashed on wake. KWin errors:
```
Atomic modeset test failed! Permission denied
Setting dpms mode failed!
```

### Attempt 2: nvidia_drm.fbdev=1

**What we did:**
```bash
# Added to GRUB:
nvidia_drm.fbdev=1
```

**Result:**
- NVIDIA GPU couldn't sleep (Video Memory: Active)
- GPU drawing 40W at idle instead of ~5W
- CPU temps spiked to 96°C
- System thermal shutdown/reboot

### Attempt 3: USB Wakeup Rules

**What we did:**
```bash
# Created /etc/udev/rules.d/90-usb-wakeup.rules:
ACTION=="add", SUBSYSTEM=="usb", DRIVERS=="usb", ATTR{power/wakeup}="enabled"
```

**Result:** No improvement to wake responsiveness.

### Attempt 4: Systemd Sleep Config

**What we did:**
```bash
# Created /etc/systemd/sleep.conf.d/deep-sleep.conf:
[Sleep]
MemorySleepMode=deep
```

**Result:** Combined with other changes, caused instability.

### Attempt 5: Switch to s2idle

**What we did:**
```bash
# Changed GRUB to:
mem_sleep_default=s2idle
```

**Result:** Still caused thermal issues and reboots after wake.

---

## Root Cause Analysis

### Why Sleep Fixes Failed

1. **KWin Wayland + Hybrid GPU Bug**
   - KDE Bug [491751](https://bugs.kde.org/show_bug.cgi?id=491751)
   - KWin fails to restore displays properly after wake
   - "Atomic modeset test failed" errors

2. **NVIDIA Power Management Conflict**
   - `nvidia_drm.fbdev=1` keeps GPU awake
   - Without it, framebuffer errors occur (harmless but annoying)
   - Browsers (Chrome, Brave, Chromium) use NVIDIA GPU keeping it at 40W

3. **Thermal Cascade**
   - Failed wake → KWin retry loops → high CPU
   - NVIDIA stuck at 40W → heat buildup
   - Eventually hits 100°C → thermal shutdown

### Log Evidence

```
# Wake failure pattern:
kwin_wayland: Atomic modeset test failed! Permission denied
kwin_wayland: Setting dpms mode failed!
kwin_wayland: Invalid framebuffer status: GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT
kwin_wayland: Failed to create framebuffer: Invalid argument

# Thermal pattern:
Core 20: +96°C (critical!)
→ System reboots
```

---

## Final Solution: REVERT TO DEFAULTS

### What We Removed

```bash
# Removed from GRUB:
sudo sed -i 's/mem_sleep_default=deep //' /etc/default/grub
sudo sed -i 's/mem_sleep_default=s2idle //' /etc/default/grub
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Removed config files:
sudo rm /etc/udev/rules.d/90-usb-wakeup.rules
sudo rm /etc/systemd/sleep.conf.d/deep-sleep.conf
```

### Current Working State

**GRUB:**
```
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1'
```

**Sleep Mode:**
```bash
$ cat /sys/power/mem_sleep
[s2idle] deep
# s2idle is default and working
```

### Trade-offs Accepted

| Issue | Status |
|-------|--------|
| Slow wake | Acceptable - system works |
| Multiple key taps to wake | Acceptable |
| Framebuffer log errors | Harmless spam |
| NVIDIA at 40W when browsers open | Known - browsers use GPU |

---

## Convenience Aliases Added

```bash
# Added to ~/.zshrc:
alias zzz='systemctl suspend'
alias suspend='systemctl suspend'
```

---

## Future Fixes (Wait for Upstream)

These issues need fixes from:
1. **KDE/KWin** - Better hybrid GPU wake handling
2. **NVIDIA Driver** - Proper D3 sleep with framebuffer
3. **Kernel** - Better Intel/NVIDIA handoff on wake

### Monitor These Bugs
- [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751) - Framebuffer errors
- [KDE Bug 477738](https://bugs.kde.org/show_bug.cgi?id=477738) - Black screen after resume

---

## Diagnostic Commands

```bash
# Check current sleep mode
cat /sys/power/mem_sleep

# Check NVIDIA power state
cat /proc/driver/nvidia/gpus/*/power | grep "Video Memory"

# Check what's using NVIDIA
lsof /dev/nvidia* 2>/dev/null | grep -v "^COMMAND"

# Monitor temps
watch -n 5 'sensors | grep -E "Package|cpu_fan" && nvidia-smi --query-gpu=power.draw --format=csv,noheader'

# Check wake logs
journalctl -b | grep -iE "suspend|resume|wake|atomic|dpms"
```

---

## Lesson Learned

> On hybrid GPU laptops with KDE Wayland, **don't try to "fix" sleep**. The default s2idle mode is the safest option until upstream fixes land. Aggressive power management causes more problems than it solves.
