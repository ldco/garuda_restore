# System Changes Changelog

**System:** ASUS TUF Gaming F15 FX507ZR
**OS:** Garuda Linux (KDE Plasma 6.5.4)
**Started:** 2025-12-29

---

## Quick Rollback Commands

```bash
# Rollback GRUB changes
sudo cp /etc/default/grub.backup /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Rollback /etc/environment
sudo cp /etc/environment.backup /etc/environment

# Re-enable Baloo for external drives
balooctl6 config remove excludeFolders /run/media/

# Remove spd5118 blacklist
sudo rm /etc/modprobe.d/blacklist-spd5118.conf

# Restore Samba config
sudo cp /etc/samba/smb.conf.backup /etc/samba/smb.conf
sudo systemctl restart smb nmb

# Re-enable Mullvad
sudo systemctl enable --now mullvad-daemon

# Remove ananicy-cpp
sudo systemctl disable --now ananicy-cpp
sudo pacman -R ananicy-cpp

# Remove MAKEFLAGS
rm ~/.config/pacman/makepkg.conf
```

---

## 2025-12-30 - Remove Conky & DDC Fix (Fix #6)

### Changes

1. **Removed conky packages** - Conky was autostarting but not being used
   ```bash
   rm ~/.config/autostart/conky.desktop
   sudo pacman -R conky-manager2 conky
   ```

2. **DDC/CI disabled via GUI** - Proper fix instead of script hack
   - System Settings → Display & Monitor → Display Configuration
   - Click each external monitor → Uncheck "Control hardware brightness with DDC/CI"
   - Setting persists across logout/login when changed via GUI

### Files Removed
- `~/.config/autostart/conky.desktop`

### Packages Removed
- `conky 1.22.2-1`
- `conky-manager2 2.7-2`

### Verification
```bash
grep allowDdcCi ~/.config/kwinoutputconfig.json
# Should show: "allowDdcCi": false for all monitors
```

### Rollback
```bash
# Re-enable DDC in GUI:
# System Settings → Display & Monitor → Display Configuration → Check DDC option

# Reinstall conky
sudo pacman -S conky conky-manager2
```

---

## 2025-12-30 - Power Profile Optimization (Fix #5)

### Problem
Fans running at 2500-2700 RPM while on AC power despite low CPU temps (55°C).

### Root Cause
asusctl was configured with `Profile on AC is Performance` which uses aggressive fan curves.

### Investigation
1. Changed AC profile from Performance → Balanced (helped)
2. Tried custom fan curves via `asusctl fan-curve` - GPU curve works, CPU curve doesn't respond properly on this laptop model
3. Tested Quiet profile - very silent but may throttle under load
4. **Final decision:** Use Balanced for cooling priority

### Fix Applied
```bash
asusctl profile -a Balanced
```

### Current Profile Configuration
```
Active profile is Balanced
Profile on AC is Balanced
Profile on Battery is Quiet
```

### Fan Behavior on Balanced
- Fans at 0 RPM when idle/cool (~55°C)
- Ramp up automatically when temps rise
- Prioritizes cooling over silence

### Note on Custom Fan Curves
Custom fan curves (`asusctl fan-curve`) were tested but:
- GPU fan curve works correctly
- CPU fan curve doesn't respond on this TUF model (firmware limitation)
- Left at default (disabled) - BIOS controls fans

### Commands
```bash
# Check profile
asusctl profile -p

# Switch for heavy workloads
asusctl profile -P Performance

# Check fan curves (informational)
asusctl fan-curve -m Balanced
```

### Rollback
```bash
asusctl profile -a Performance
```

---

## 2025-12-30 - Mesa Upgrade (Fix #4)

### Context
Mesa was downgraded to 25.2.7 while debugging cursor lag. After fixing the real cause
(KWIN_DRM_NO_AMS=1), Mesa was upgraded back to latest.

### Change
```bash
sudo pacman -S mesa lib32-mesa
# 25.2.7 → 25.3.2
```

### Result
System working fine with Mesa 25.3.2. Cursor lag was NOT caused by Mesa.

---

## 2025-12-30 - Cursor Lag Fix (Fix #3)

### Problem
- Mouse cursor lagging on external monitors (DP-1, HDMI-A-1)
- Built-in screen (eDP-2) was smooth
- KWin at 40-47% CPU constantly
- Journal showing: `Libinput: client bug: event processing lagging behind by 26ms, your system is too slow`

### Root Cause
`KWIN_DRM_NO_AMS=1` was forcing KWin into "legacy mode" instead of efficient Atomic Mode Setting.
This was originally set to prevent DDC/i2c crashes, but DDC is now disabled per-monitor.

Journal showed:
```
Atomic Mode Setting requested off via environment variable. Using legacy mode on GPU
```

### Fix Applied
Removed `KWIN_DRM_NO_AMS=1` from `~/.config/environment.d/kwin-fixes.conf`

Also disabled DDC/CI per-monitor in `~/.config/kwinoutputconfig.json`:
```json
"allowDdcCi": false
```

### Files Modified
- `~/.config/environment.d/kwin-fixes.conf` - Removed KWIN_DRM_NO_AMS=1
- `~/.config/kwinoutputconfig.json` - Set allowDdcCi=false for all monitors

### Current kwin-fixes.conf
```bash
# Disable DDC brightness control - prevents display crashes on hybrid GPU
# Crash signature: org_kde_powerdevil "No Display_Ref found for i2c bus"
# DDC also disabled per-monitor in kwinoutputconfig.json (allowDdcCi=false)
POWERDEVIL_NO_DDCUTIL=1
```

### Verification
```bash
# Should NOT show "legacy mode"
journalctl -b | grep -i "atomic\|legacy" | head -5

# Should be ~5-15% not 40%+
ps aux | grep kwin

# Cursor should be smooth on all monitors
```

### Rollback
```bash
# Add back to ~/.config/environment.d/kwin-fixes.conf:
echo "KWIN_DRM_NO_AMS=1" >> ~/.config/environment.d/kwin-fixes.conf
# Then logout/login
```

### Note
If DDC crashes return, the per-monitor `allowDdcCi=false` setting should prevent them.
If crashes still occur, re-add `KWIN_DRM_NO_AMS=1`.

---

## 2025-12-30 - Remove nvidia_drm.fbdev=1 (Fix #2)

### Problem
After GPU order fix, fans still at 2500-2700 RPM instead of 1500/1200.
NVIDIA GPU drawing 22W at idle (3% utilization) - should be ~5W or sleeping.

### Root Cause
`nvidia_drm.fbdev=1` in GRUB keeps NVIDIA GPU awake (Video Memory: Active).
Even though Intel is rendering, NVIDIA can't enter D3 sleep state.

### Fix Applied
Remove `nvidia_drm.fbdev=1` from GRUB:

**Before:**
```
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1'
```

**After:**
```
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1'
```

### Command
```bash
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub && sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Files Modified
- `/etc/default/grub`

### Trade-off
- **Pro:** NVIDIA can fully sleep, fans drop to 1500/1200 RPM, lower power
- **Con:** KWin framebuffer log errors return (harmless spam)

### Verification
```bash
# After reboot:
sensors | grep -E "cpu_fan|gpu_fan"
# Expected: ~1500 RPM / ~1200 RPM

cat /proc/driver/nvidia/gpus/*/power | grep "Video Memory"
# Expected: Off (not Active)
```

### Rollback
```bash
sudo sed -i 's/nvidia_drm.modeset=1/nvidia_drm.modeset=1 nvidia_drm.fbdev=1/' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

---

## 2025-12-30 - GPU Rendering Fix (Fix #1)

### Problem
After 2025-12-29 fixes, system crashed. After reboot/login:
- CPU fan: 3300 RPM
- GPU fan: 3000 RPM
- NVIDIA GPU drawing 65W at idle
- All apps rendering on NVIDIA instead of Intel

### Root Cause
`KWIN_DRM_DEVICES` was set with NVIDIA first:
```
KWIN_DRM_DEVICES=/dev/dri/card1:/dev/dri/card2
```
This made NVIDIA the primary GPU for all rendering.

### Fix Applied
Changed to Intel first:
```
KWIN_DRM_DEVICES=/dev/dri/card2:/dev/dri/card1
```

### Files Modified
- `/etc/environment` - Swapped GPU order

### Verification
```bash
# After logout/login:
sensors | grep -E "cpu_fan|gpu_fan"
# Expected: ~1500 RPM / ~1200 RPM

nvidia-smi --query-gpu=power.draw --format=csv,noheader
# Expected: ~15-25W (not 65W)
```

---

## 2025-12-29 - Initial System Optimization

### Overview
Full system analysis and optimization performed. All changes documented in [FIX-PLAN.md](../fixes/FIX-PLAN.md).

---

### Change 1: Btrfs Health Verification
**Priority:** CRITICAL
**Status:** Verified healthy

```bash
sudo btrfs device stats /
# Result: All zeros (healthy)

sudo btrfs scrub start /
sudo btrfs scrub status /
# Result: No errors found
```

**Files Modified:** None (read-only check)

---

### Change 2: Samba Security Hardening
**Priority:** HIGH
**Status:** Applied

**Before:**
```
# Samba listening on 0.0.0.0:445 (all interfaces)
```

**After:**
```ini
# /etc/samba/smb.conf [global] section:
interfaces = 127.0.0.1 192.168.1.5
bind interfaces only = yes
```

**Files Modified:**
- `/etc/samba/smb.conf`
- Backup: `/etc/samba/smb.conf.backup`

**Verification:**
```bash
ss -tlnp | grep -E "139|445"
# Should show 127.0.0.1 and 192.168.1.x, NOT 0.0.0.0
```

---

### Change 3: Blacklist spd5118 DDR5 Sensor
**Priority:** HIGH
**Status:** Applied

**Purpose:** Stop DDR5 sensor driver causing resume errors

**Files Created:**
- `/etc/modprobe.d/blacklist-spd5118.conf`
  ```
  blacklist spd5118
  ```

**Verification:**
```bash
lsmod | grep spd5118
# Should return nothing (module not loaded)
```

**Trade-off:** DDR5 temperature monitoring disabled

---

### Change 4: GRUB NVIDIA Parameters
**Priority:** HIGH
**Status:** Applied

**Before:**
```
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3'
```

**After:**
```
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1'
```

**Files Modified:**
- `/etc/default/grub`
- Backup: `/etc/default/grub.backup`

**Commands Run:**
```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

**Purpose:** Enable NVIDIA framebuffer for KWin hybrid GPU support

**Note:** This combined with incorrect KWIN_DRM_DEVICES caused the 2025-12-30 high fan issue.

---

### Change 5: GRUB Timeout Reduction
**Priority:** LOW
**Status:** Applied (combined with Change 4)

**Before:**
```
GRUB_TIMEOUT=5
```

**After:**
```
GRUB_TIMEOUT=2
```

**Files Modified:** Same as Change 4

---

### Change 6: Pacman Parallel Downloads
**Priority:** LOW
**Status:** Applied

**Before:**
```
ParallelDownloads = 5
```

**After:**
```
ParallelDownloads = 10
```

**Files Modified:**
- `/etc/pacman.conf`

**Verification:**
```bash
grep ParallelDownloads /etc/pacman.conf
```

---

### Change 7: Disable Mullvad VPN Daemon
**Priority:** LOW
**Status:** Applied

**Command:**
```bash
sudo systemctl disable --now mullvad-daemon
```

**Verification:**
```bash
systemctl is-active mullvad-daemon
# Should show: inactive
```

**Rollback:**
```bash
sudo systemctl enable --now mullvad-daemon
```

---

### Change 8: Baloo Exclude External Drives
**Priority:** HIGH
**Status:** Applied
**Impact:** BIGGEST temperature improvement!

**Problem:** Baloo was indexing 2+ million files from `/run/media/` causing:
- CPU at 85-92C
- Fans at 3400+ RPM
- `baloo_file` using 18% CPU

**Commands:**
```bash
balooctl6 config add excludeFolders /run/media/
pkill -9 baloo_file
balooctl6 purge
balooctl6 enable
```

**Files Modified:**
- `~/.config/baloofilerc`

**Results:**
| Metric | Before | After |
|--------|--------|-------|
| CPU Temp | 85-92C | 49-57C |
| CPU Fan | 3400 RPM | 1500 RPM |
| GPU Fan | 3000 RPM | 1200 RPM |

**Verification:**
```bash
balooctl6 config
# Should show: exclude folders[$e]=/run/media/
```

---

### Change 9: Install ananicy-cpp
**Priority:** MEDIUM
**Status:** Applied

**Purpose:** Auto-prioritize processes for desktop responsiveness

**Commands:**
```bash
paru -S ananicy-cpp
sudo systemctl enable --now ananicy-cpp
```

**Packages Installed:**
- `ananicy-cpp`

**Verification:**
```bash
systemctl is-active ananicy-cpp
pacman -Q ananicy-cpp
```

---

### Change 10: MAKEFLAGS for AUR Builds
**Priority:** LOW
**Status:** Applied

**Purpose:** Use all 20 CPU threads for AUR compilation

**Files Created:**
- `~/.config/pacman/makepkg.conf`
  ```
  MAKEFLAGS="-j$(nproc)"
  ```

**Verification:**
```bash
cat ~/.config/pacman/makepkg.conf
```

---

### Change 11: KWin Environment Variables
**Priority:** HIGH
**Status:** Applied (later fixed on 2025-12-30)

**Files Modified:**
- `/etc/environment`

**Content Added:**
```bash
# KWin hybrid GPU stability fixes (2025-12-29)
# card1 = NVIDIA RTX 3070, card2 = Intel Iris Xe
KWIN_DRM_DEVICES=/dev/dri/card1:/dev/dri/card2  # WRONG ORDER - fixed 2025-12-30

# Enable NVIDIA colorspace handling (fixes framebuffer errors)
KWIN_DRM_ALLOW_NVIDIA_COLORSPACE=1
```

**Note:** The GPU order was wrong (NVIDIA first). Fixed on 2025-12-30.

---

## Summary of All Modified Files

| File | Change | Backup |
|------|--------|--------|
| `/etc/default/grub` | NVIDIA params + timeout | `/etc/default/grub.backup` |
| `/etc/samba/smb.conf` | Bind to local interfaces | `/etc/samba/smb.conf.backup` |
| `/etc/modprobe.d/blacklist-spd5118.conf` | Created | N/A |
| `/etc/pacman.conf` | ParallelDownloads=10 | N/A |
| `/etc/environment` | KWin GPU config | backup created |
| `~/.config/baloofilerc` | Exclude /run/media/ | N/A |
| `~/.config/pacman/makepkg.conf` | Created | N/A |

## Services Changed

| Service | Action | Rollback |
|---------|--------|----------|
| mullvad-daemon | disabled | `sudo systemctl enable --now mullvad-daemon` |
| ananicy-cpp | enabled | `sudo systemctl disable --now ananicy-cpp` |
| smb/nmb | restarted | N/A |

## Packages Installed

| Package | Purpose |
|---------|---------|
| ananicy-cpp | Process auto-prioritization |

---

## Health Check After All Changes

```bash
echo "=== BTRFS ===" && sudo btrfs device stats /
echo "=== TEMPS ===" && sensors | grep -E "Package|cpu_fan|gpu_fan"
echo "=== NVIDIA ===" && nvidia-smi --query-gpu=power.draw,utilization.gpu --format=csv,noheader
echo "=== BALOO ===" && balooctl6 status
echo "=== SERVICES ===" && systemctl is-active ananicy-cpp mullvad-daemon
```

**Expected Results (after 2025-12-30 fix):**
- BTRFS: All zeros
- CPU Temp: 50-65C
- CPU Fan: 1500-2000 RPM
- GPU Fan: 1200-1500 RPM
- NVIDIA: 15-25W, 0-5% utilization
- Baloo: Idle
- ananicy-cpp: active
- mullvad-daemon: inactive
