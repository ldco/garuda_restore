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
| Baloo exclude /run/media/ | ✅ | Temps dropped 20°C (biggest impact!) |
| ananicy-cpp | ✅ | Process auto-prioritizer active |
| MAKEFLAGS for AUR | ✅ | 20 parallel threads |

### Remaining Note
- KWin still logs ~139 framebuffer warnings (KDE Bug 491751)
- These are non-critical GL_FRAMEBUFFER_INCOMPLETE errors in hybrid GPU
- System is stable; may improve with future KDE/Mesa updates

---

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

See [KWIN-HYBRID-GPU.md](KWIN-HYBRID-GPU.md) for full details.

### Fix 5: Baloo File Indexer (HIGH)
**Problem:** Baloo indexing 2M+ files from external drive, causing 85°C CPU temps
**Solution:** Exclude `/run/media/` from baloo config
**Config:** `~/.config/baloofilerc`
**Impact:** Temps dropped 20°C, fans dropped 50-60%

### Fix 6: ananicy-cpp Process Prioritizer (MEDIUM)
**Problem:** No automatic process prioritization
**Solution:** Install and enable ananicy-cpp
**Risk:** None - improves desktop responsiveness

### Fix 7: MAKEFLAGS for AUR Builds (LOW)
**Problem:** AUR packages compile with single thread
**Solution:** Add `MAKEFLAGS="-j$(nproc)"` to `~/.config/pacman/makepkg.conf`
**Risk:** None - uses all 20 CPU threads for compilation

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
