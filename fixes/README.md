# System Fixes

Fixes identified from [SYSTEM-ANALYSIS.md](../docs/SYSTEM-ANALYSIS.md).

## Status: ✅ ALL VERIFIED (2025-12-29)

All fixes applied and verified after reboot.

### Verified Fixes
| Fix | Status | Verification |
|-----|--------|--------------|
| Btrfs health check | ✅ | Scrub completed, no errors |
| spd5118 blacklist | ✅ | `lsmod \| grep spd5118` = empty |
| KWin nvidia_drm.fbdev=1 | ✅ | `/proc/cmdline` shows params |
| GRUB timeout | ✅ | 2 seconds |
| Pacman parallel | ✅ | 10 downloads |
| Mullvad daemon | ✅ | Disabled |
| Samba bind local | ✅ | Bound to 127.0.0.1 + 192.168.1.5 |

### Remaining Note
- KWin still logs ~139 framebuffer warnings (KDE Bug 491751)
- These are non-critical GL_FRAMEBUFFER_INCOMPLETE errors in hybrid GPU
- System is stable; may improve with future KDE/Mesa updates

---

## Quick Apply (Interactive)

```bash
./apply-fixes.sh
```

This script will:
- Ask confirmation for each fix
- Create backups before changes
- Provide rollback instructions

## Individual Fixes

| File | Priority | Description | Status |
|------|----------|-------------|--------|
| [01-samba-bind-local.conf](01-samba-bind-local.conf) | HIGH | Bind Samba to local network only | ✅ Verified |
| [02-blacklist-spd5118.conf](02-blacklist-spd5118.conf) | HIGH | Fix DDR5 sensor resume errors | ✅ Verified |
| [03-grub-optimizations.conf](03-grub-optimizations.conf) | LOW | Reduce GRUB timeout | ✅ Verified |
| [04-kwin-hybrid-gpu.md](04-kwin-hybrid-gpu.md) | HIGH | KWin nvidia_drm.fbdev=1 fix | ✅ Verified |

## Fix Details

### Fix 1: Samba Security (HIGH)
**Problem:** Samba ports 139/445 exposed on 0.0.0.0
**Solution:** Bind to 127.0.0.1 and 192.168.1.0/24 only
**Risk:** Low - only affects remote access

### Fix 2: SPD5118 Blacklist (HIGH)
**Problem:** DDR5 temperature sensor causes resume errors
**Solution:** Blacklist the spd5118 kernel module
**Risk:** Low - only loses DDR5 temp monitoring

### Fix 3: GRUB Timeout (LOW)
**Problem:** 5 second boot delay
**Solution:** Reduce to 2 seconds
**Risk:** Minimal

### Fix 4: KWin GPU Errors (MEDIUM)
**Problem:** Framebuffer errors in hybrid GPU setup (Intel + NVIDIA on Wayland)
**Bug:** [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751)
**Potential Fixes (power-safe, won't overheat):**
1. `nvidia_drm.fbdev=1` kernel param (recommended first)
2. Disable ICC profiles in KDE settings
3. `KWIN_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1` (Intel first)
4. `KWIN_DRM_ALLOW_NVIDIA_COLORSPACE=1` (experimental)

See [04-kwin-hybrid-gpu.md](04-kwin-hybrid-gpu.md) for full details.

## Not Fixed (Manual Review Needed)

### Btrfs "MISSING" Status
- **Status:** Cosmetic issue only
- **Cause:** Intel VMD RAID controller
- **Action:** Run periodic scrub: `sudo btrfs scrub start /`

### Memory Temperature (60C)
- **Status:** Hardware limitation
- **Action:** Ensure cooling vents are clean, use cooling pad

### High Memory Usage (71%)
- **Status:** User workload (3 browsers, VS Code, etc.)
- **Action:** Close unused applications

## Rollback

All fixes create backups. To rollback:

```bash
# Samba
sudo cp ~/.config/system-fixes-backup-*/smb.conf.backup /etc/samba/smb.conf
sudo systemctl restart smb nmb

# SPD5118
sudo rm /etc/modprobe.d/blacklist-spd5118.conf
sudo reboot

# GRUB
sudo cp ~/.config/system-fixes-backup-*/grub.backup /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```
