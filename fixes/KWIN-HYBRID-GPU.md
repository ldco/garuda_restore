# KWin Hybrid GPU Framebuffer Errors

## Status: ✅ FIXED (2025-12-29)
Option 1 (nvidia_drm.fbdev=1) has been applied. Reboot required.

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

## Potential Fixes (Power-Safe Options)

### Option 1: nvidia_drm.fbdev=1 ✅ APPLIED

Enables proper framebuffer support in NVIDIA driver without forcing NVIDIA for all rendering.

```bash
# Add to /etc/default/grub:
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1'

# Apply:
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

**Risk:** Low - just enables framebuffer device
**Source:** [Arch Forums](https://bbs.archlinux.org/viewtopic.php?id=295937)

### Option 2: Disable ICC Profiles (Zero Risk)

From KDE Bug 491751 - users reported this significantly reduced errors:

1. System Settings → Display & Monitor
2. Color Calibration → Disable all profiles

**Risk:** None - only affects color calibration
**Source:** [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751)

### Option 3: KWIN_DRM_DEVICES with Intel First (Low Risk)

Tell KWin about both GPUs explicitly, keeping Intel as primary:

```bash
# Add to /etc/environment:
KWIN_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1
```

This keeps Intel primary (power saving) but informs KWin about NVIDIA.

**Risk:** Low - may improve or have no effect
**Source:** [GitHub Gist](https://gist.github.com/bugra455/b40d7f505beec6bea514af7cf618fcf5)

### Option 4: KWIN_DRM_ALLOW_NVIDIA_COLORSPACE (Experimental)

For Plasma 6.2+, may help with color/framebuffer handling:

```bash
# Add to /etc/environment:
KWIN_DRM_ALLOW_NVIDIA_COLORSPACE=1
```

**Risk:** Low - experimental feature
**Source:** [EndeavourOS Forum](https://forum.endeavouros.com/t/wayland-kde-6-optimus-nvidia/52991/16)

---

## NOT Recommended (Causes Overheating)

| "Fix" | Why NOT applicable |
|-------|-------------------|
| NVIDIA for all displays | RTX 3070 = 115W TDP = overheating |
| Use X11 | Need Wayland features |
| Disable external monitors | Defeats triple-monitor setup |

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

---

## Testing Order

1. **Try Option 1** (nvidia_drm.fbdev=1) - most likely to help
2. **Try Option 2** (disable ICC) - zero risk
3. **Try Option 3** (KWIN_DRM_DEVICES) - if still issues
4. **Try Option 4** (colorspace) - experimental

After each change, check error count:
```bash
# Before
journalctl -b | grep -c "framebuffer"

# After reboot
journalctl -b | grep -c "framebuffer"
```

---

## References

- [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751)
- [Arch Linux Forums - Wayland NVIDIA Fix](https://bbs.archlinux.org/viewtopic.php?id=295937)
- [GitHub Gist - KDE6 NVIDIA Animation Fix](https://gist.github.com/bugra455/b40d7f505beec6bea514af7cf618fcf5)
- [Kextcache - Wayland NVIDIA 2025 Guide](https://kextcache.com/wayland-nvidia-a-definite-2025-guide/)
- [David Edmundson - KWin Wayland on NVIDIA](https://blog.davidedmundson.co.uk/blog/running-kwin-wayland-on-nvidia/)
