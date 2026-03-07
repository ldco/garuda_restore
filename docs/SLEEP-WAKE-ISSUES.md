# Sleep/Wake Issues - Troubleshooting History

## Current Status: TARGETED FIX AVAILABLE (2026-03-07)

### Decision Guide: Should You Apply This Fix?

| Your Symptom | Action |
|--------------|--------|
| Login screen works after sleep, but **desktop freezes after login** | **Apply the fix** (this document) |
| Login screen itself is frozen (can't type password) | Try `fix-sddm-input.sh` instead |
| System wakes fine, no freezes | **Do nothing** - defaults work |
| Fix causes thermal issues or instability | **Rollback** to defaults |

### Active Fix: KWin Compositor Freeze

**Applies to:** KDE Plasma Wayland with hybrid GPU (Intel + NVIDIA)

Run this script to apply the KWin recovery fix:
```bash
sudo ./scripts/fix-sleep-kwin.sh
```

This installs a sleep hook that:
1. Resets Intel backlight controller after wake (common freeze source)
2. Forces DRM/display subsystem reprobe
3. Restarts KWin compositor via D-Bus with proper user session context
4. Logs GPU power state before/after for thermal validation

**Logs:** `/var/log/kwin-sleep.log`

**Log Retention:** See [Log File Management](#log-file-management) below for rotation and truncation guidance.

**Verify Success:**
```bash
# After suspend and wake, check:
tail /var/log/kwin-sleep.log
# Should show "KWin restart SUCCESS" and "RESUME COMPLETE"

# System should be responsive after login
ps aux | grep kwin_wayland  # Should show running process
```

**Rollback to Defaults:**
```bash
sudo rm -f /usr/lib/systemd/system-sleep/99-kwin-fix
sudo udevadm control --reload-rules
```

---

## Historical Status: REVERTED TO DEFAULTS (2025-12-31)

All previous sleep "fixes" caused system instability (thermal reboots). Reverted to system defaults.

**Why those fixes failed:** They modified GRUB kernel parameters and NVIDIA driver behavior, which caused thermal cascade on this hybrid GPU system.

**Why this fix is different:** It does NOT change kernel parameters or driver settings. It only:
- Resets display backlight state (hardware-level, no driver changes)
- Triggers existing kernel subsystems (DRM, input)
- Restarts the frozen userspace compositor (KWin)

The fix works *with* the system defaults, not against them.

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

> On hybrid GPU laptops with KDE Wayland, **don't try to "fix" sleep with kernel parameters or driver modifications**. The default s2idle mode is the safest option until upstream fixes land. Aggressive power management (GRUB params, NVIDIA framebuffer hacks) causes more problems than it solves.

> **Exception:** The targeted KWin compositor restart hook (`fix-sleep-kwin.sh`) is the approved fix for the specific symptom of **post-login freeze after sleep**. This fix works at the userspace level without modifying kernel or driver behavior, making it safe to use alongside default system settings.

### Recommendation Hierarchy

1. **First:** Use system defaults (s2idle, no GRUB modifications)
2. **If post-login freeze occurs:** Apply `fix-sleep-kwin.sh` (userspace compositor restart only)
3. **If login screen input is frozen:** Try `fix-sddm-input.sh` (input module reload)
4. **Never:** Modify GRUB with `nvidia_drm.fbdev=1`, `mem_sleep_default=deep`, or similar on this hardware
5. **Always:** Rollback any fix that causes thermal instability

---

## Log File Management

### Custom Sleep Hook Logs

The sleep fix scripts create log files that can grow unbounded on frequently suspended systems:

| Log File | Created By | Typical Size |
|----------|------------|--------------|
| `/var/log/kwin-sleep.log` | `fix-sleep-kwin.sh` | ~500 bytes per suspend cycle |
| `/var/log/sddm-input-reset.log` | `fix-sddm-input.sh` | ~200 bytes per suspend cycle |

**Example:** 10 suspend cycles/day = ~5KB/day = ~1.8MB/year per log file.

### Automatic Rotation (Recommended)

A logrotate configuration is provided in `scripts/kwin-sleep-logrotate.conf`. Install it with:

```bash
sudo cp scripts/kwin-sleep-logrotate.conf /etc/logrotate.d/kwin-sleep
```

**Manual alternative** (if you prefer not to use the config file):
```bash
sudo tee /etc/logrotate.d/kwin-sleep > /dev/null << 'EOF'
/var/log/kwin-sleep.log /var/log/sddm-input-reset.log {
    missingok
    notifempty
    size 100K
    rotate 5
    compress
    delaycompress
    create 0644 root root
}
EOF
```

**Policy:**
- Rotate when file exceeds 100KB
- Keep 5 rotated copies (max ~500KB total)
- Compress old logs to save space

### Manual Truncation (During Diagnostics)

When actively debugging sleep issues, you may need to truncate logs:

```bash
# Safe truncation (preserves file, clears content)
sudo truncate -s 0 /var/log/kwin-sleep.log
sudo truncate -s 0 /var/log/sddm-input-reset.log

# Alternative using shell redirection
sudo sh -c '> /var/log/kwin-sleep.log'
sudo sh -c '> /var/log/sddm-input-reset.log'
```

**⚠️ Do NOT use `rm`** during active diagnostics - the sleep hook expects the file to exist and will recreate it if missing, but this can cause race conditions.

### Quick Health Check

```bash
# Check log sizes
ls -lh /var/log/kwin-sleep.log /var/log/sddm-input-reset.log

# Check rotation status
logrotate -d /etc/logrotate.d/kwin-sleep 2>&1 | head -20
```

See also: [`docs/QUICK-REFERENCE.md`](QUICK-REFERENCE.md) for daily operational commands.
