# KWin Hybrid GPU Framebuffer Errors

## ⚠️ APPROVED HIERARCHY & THERMAL SAFETY POLICY

**This document's guidance is DEPRECATED for sleep/wake issues.** Refer to [`SLEEP-WAKE-ISSUES.md`](SLEEP-WAKE-ISSUES.md) for the current approved policy.

### Decision Hierarchy (Authoritative: SLEEP-WAKE-ISSUES.md)

1. **FIRST:** Use system defaults (s2idle, no GRUB modifications)
2. **IF post-login freeze occurs:** Apply `scripts/fix-sleep-kwin.sh` (userspace compositor restart only)
3. **IF login screen input is frozen:** Try `scripts/fix-sddm-input.sh` (input module reload)
4. **NEVER:** Modify GRUB with `nvidia_drm.fbdev=1`, `mem_sleep_default=deep`, or similar on this hardware
5. **ALWAYS:** Rollback any fix that causes thermal instability

### ⚠️ Deprecated Recommendations in This Document

This document historically recommended `nvidia_drm.fbdev=1` as a potential fix for framebuffer errors. **This is now DEPRECATED** due to:

- GPU stuck at 40W idle instead of ~5W
- System overheating to 96°C causing thermal shutdown/reboot
- NVIDIA video memory staying active during suspend

**Action:** If you applied `nvidia_drm.fbdev=1` from this document, **roll it back immediately** per [`SLEEP-WAKE-ISSUES.md`](SLEEP-WAKE-ISSUES.md).

---

## Status: ⚠️ REVERTED (2025-12-31)

`nvidia_drm.fbdev=1` was removed - it caused thermal issues (GPU stuck at 40W, system overheating to 96°C and rebooting).

**Current state:** Framebuffer log errors occur but are **harmless**. System is stable.

---

## Problem
```
kwin_wayland: Invalid framebuffer status: "GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT"
kwin_wayland: Invalid framebuffer status: "GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT"
```

## Setup
- **card1** = NVIDIA RTX 3070 (DP-1, HDMI-A-1, eDP-1)
- **card2** = Intel Iris Xe (DP-2, DP-3, eDP-2)
- Wayland + KWin compositor
- Triple 1440p monitors

## Bug Tracker
- [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751) - Status: REPORTED (unresolved)
- Root cause: NVIDIA driver bug per KDE developer Zamundaaa

---

## Historical Context: Why These "Fixes" Were Removed

The following options were documented as potential fixes but **caused thermal instability** on this hardware profile (ASUS TUF Gaming F15 FX507ZR with RTX 3070 Mobile):

### Option 1: nvidia_drm.fbdev=1 ❌ REMOVED

**Was documented as:**
```bash
# Add to /etc/default/grub:
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1'
```

**Why removed:**
- NVIDIA GPU couldn't enter D3 sleep state
- Video Memory stayed Active instead of suspended
- GPU drew 40W at idle instead of ~5W
- CPU temps spiked to 96°C → thermal shutdown

**Rollback:**
```bash
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Option 2: Disable ICC Profiles ✅ SAFE (Zero Risk)

From KDE Bug 491751 - users reported this significantly reduced errors:

1. System Settings → Display & Monitor
2. Color Calibration → Disable all profiles

**Status:** Still safe to use - only affects color calibration, no driver changes.

### Option 3: KWIN_DRM_DEVICES with Intel First ⚠️ NOT RECOMMENDED

**Was documented as:**
```bash
# Add to /etc/environment:
KWIN_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1
```

**Why not recommended:** Modifies KWin behavior in ways that can conflict with sleep/wake recovery. See [`SLEEP-WAKE-ISSUES.md`](SLEEP-WAKE-ISSUES.md) for the approved userspace fix.

### Option 4: KWIN_DRM_ALLOW_NVIDIA_COLORSPACE ⚠️ EXPERIMENTAL

**Status:** Experimental feature - not tested with current sleep fix. Use at own risk.

---

## NOT Recommended (Causes Overheating)

| "Fix" | Why NOT applicable |
|-------|-------------------|
| NVIDIA for all displays | RTX 3070 = 115W TDP = overheating |
| Use X11 | Need Wayland features |
| Disable external monitors | Defeats triple-monitor setup |
| `nvidia_drm.fbdev=1` | Causes thermal cascade (see above) |
| `mem_sleep_default=deep` | System crashed on wake |

---

## Workaround: Reduce Log Spam

If logs filling up is a concern:

```bash
# Limit journal size
sudo journalctl --vacuum-size=500M
```

Or add to `/etc/systemd/journald.conf`:
```ini
SystemMaxUse=500M
```

**Note:** Framebuffer errors are harmless visual noise in logs - they don't indicate actual display problems.

---

## References

- [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751)
- [Arch Linux Forums - Wayland NVIDIA Fix](https://bbs.archlinux.org/viewtopic.php?id=295937)
- [GitHub Gist - KDE6 NVIDIA Animation Fix](https://gist.github.com/bugra455/b40d7f505beec6bea514af7cf618fcf5)
- [Kextcache - Wayland NVIDIA 2025 Guide](https://kextcache.com/wayland-nvidia-a-definite-2025-guide/)
- [David Edmundson - KWin Wayland on NVIDIA](https://blog.davidedmundson.co.uk/blog/running-kwin-wayland-on-nvidia/)

---

## See Also

- [`SLEEP-WAKE-ISSUES.md`](SLEEP-WAKE-ISSUES.md) - **Authoritative** sleep/wake troubleshooting and approved fixes
- [`QUICK-REFERENCE.md`](QUICK-REFERENCE.md) - Daily commands and optimal baselines
