# System Fix Plan

**Date:** 2025-12-29
**Status:** ✅ ALL FIXES VERIFIED (2025-12-29)
**Approach:** Careful, one step at a time, with verification

---

## Priority Order

| Step | Priority | Issue | Risk | Reboot? |
|------|----------|-------|------|---------|
| 1 | CRITICAL | Btrfs health check | None (read-only) | No |
| 2 | HIGH | Samba bind to local | Low | No |
| 3 | HIGH | Blacklist spd5118 | Low | Yes |
| 4 | HIGH | KWin nvidia_drm.fbdev=1 | Low | Yes |
| 5 | LOW | GRUB timeout reduction | Minimal | No* |
| 6 | LOW | Pacman parallel downloads | None | No |
| 7 | LOW | Disable unused daemons | None | No |
| 8 | HIGH | Baloo exclude /run/media/ | None | No |
| 9 | MEDIUM | Install ananicy-cpp | None | No |
| 10 | LOW | MAKEFLAGS for AUR builds | None | No |

*Combined with step 4 reboot

---

## Step 1: Btrfs Health Check (CRITICAL)

**Purpose:** Verify filesystem integrity before making any changes

### Commands (Read-Only - Safe)
```bash
# 1. Check for actual errors
sudo btrfs device stats /

# 2. If all zeros = healthy, start background scrub
sudo btrfs scrub start /

# 3. Check scrub status (can take 10-30 min)
sudo btrfs scrub status /
```

### Expected Results
- `device stats` should show all zeros
- If errors found: STOP and investigate before proceeding
- Scrub runs in background, system usable

### Verification
```bash
# After scrub completes:
sudo btrfs scrub status /
# Should show: "no errors found"
```

---

## Step 2: Samba Security (HIGH)

**Purpose:** Bind Samba to local network only, not 0.0.0.0

### Backup First
```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
```

### Apply Fix
```bash
# Add these lines after [global] section in /etc/samba/smb.conf:
sudo nano /etc/samba/smb.conf

# Add after "workgroup = WORKGROUP":
#    interfaces = 127.0.0.1 192.168.1.0/24
#    bind interfaces only = yes
```

### Restart Service
```bash
sudo systemctl restart smb nmb
```

### Verification
```bash
# Before: shows 0.0.0.0:445
# After: should show 192.168.1.x:445
ss -tlnp | grep -E "139|445"
```

### Rollback (if issues)
```bash
sudo cp /etc/samba/smb.conf.backup /etc/samba/smb.conf
sudo systemctl restart smb nmb
```

---

## Step 3: Blacklist spd5118 (HIGH)

**Purpose:** Stop DDR5 sensor driver causing resume errors

### Apply Fix
```bash
echo "blacklist spd5118" | sudo tee /etc/modprobe.d/blacklist-spd5118.conf
```

### Note
- Requires reboot to take effect
- Will be combined with Step 4 reboot
- DDR5 temperature monitoring will be disabled (acceptable trade-off)

### Verification (after reboot)
```bash
# Should return nothing (module not loaded)
lsmod | grep spd5118

# Check journal for resume errors - should be gone
journalctl -b | grep -c spd5118
```

### Rollback
```bash
sudo rm /etc/modprobe.d/blacklist-spd5118.conf
sudo reboot
```

---

## Step 4: KWin nvidia_drm.fbdev=1 (HIGH)

**Purpose:** Enable NVIDIA framebuffer support to reduce KWin errors

### Check Current Framebuffer Error Count
```bash
# Record this number
journalctl -b | grep -c "framebuffer"
```

### Backup GRUB Config
```bash
sudo cp /etc/default/grub /etc/default/grub.backup
```

### Edit GRUB
```bash
sudo nano /etc/default/grub

# Change this line:
# FROM: GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3'
# TO:   GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1'
```

### Also Apply Step 5 (GRUB Timeout)
```bash
# While in /etc/default/grub, also change:
# FROM: GRUB_TIMEOUT=5
# TO:   GRUB_TIMEOUT=2
```

### Regenerate GRUB
```bash
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Reboot
```bash
sudo reboot
```

### Verification (after reboot)
```bash
# Check new framebuffer error count
journalctl -b | grep -c "framebuffer"
# Should be significantly lower than before

# Verify nvidia params applied
cat /proc/cmdline | grep nvidia
# Should show: nvidia_drm.modeset=1 nvidia_drm.fbdev=1

# Verify GRUB timeout
grep GRUB_TIMEOUT /etc/default/grub
# Should show: GRUB_TIMEOUT=2
```

### Rollback (if issues)
```bash
sudo cp /etc/default/grub.backup /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

---

## Step 5: GRUB Timeout (LOW)

**Included in Step 4** - applied together to minimize reboots.

---

## Step 6: Pacman Parallel Downloads (LOW)

**Purpose:** Faster package downloads

### Edit pacman.conf
```bash
sudo nano /etc/pacman.conf

# Find and change:
# FROM: ParallelDownloads = 5
# TO:   ParallelDownloads = 10
```

### Verification
```bash
grep ParallelDownloads /etc/pacman.conf
# Should show: ParallelDownloads = 10
```

### Test
```bash
# Next time you run pacman -Syu, it will download 10 packages at once
```

---

## Step 7: Disable Unused Daemons (LOW)

**Purpose:** Stop services you're not using to reduce resource usage

### Disable (Not Using)

```bash
# Mullvad VPN - not using (can re-enable anytime with: sudo systemctl enable --now mullvad-daemon)
sudo systemctl disable --now mullvad-daemon
```

### Keep Running (Harmless)

| Service | Why Keep |
|---------|----------|
| `ModemManager` | Needed if you ever use USB 4G dongle, minimal resources |
| `bluetooth` | Software-blocked but service ready if you unblock it |

### Consider Disabling (If Not Needed)

| Service | Keep if... | Disable command |
|---------|------------|-----------------|
| `avahi-daemon` | Network printers, Chromecast | `sudo systemctl disable --now avahi-daemon` |
| `cups` | Have printers | `sudo systemctl disable --now cups` |
| `bolt` | Use Thunderbolt docks | `sudo systemctl disable --now bolt` |

### Verification
```bash
# Verify mullvad stopped
systemctl is-active mullvad-daemon
# Should show: inactive
```

### Rollback
```bash
sudo systemctl enable --now mullvad-daemon
```

---

## Step 8: Baloo Exclude External Drive (HIGH)

**Purpose:** Stop KDE file indexer from indexing external drives (causes high CPU/temps)

### Background
Baloo was indexing 2+ million files from `/run/media/` causing:
- CPU at 85-92°C
- Fans at 3000+ RPM
- `baloo_file` process using 18% CPU

### Apply Fix
```bash
# Exclude external drives from indexing
balooctl6 config add excludeFolders /run/media/

# Kill baloo and purge the index
pkill -9 baloo_file
balooctl6 purge

# Restart baloo
balooctl6 enable
```

### Verification
```bash
# Check excluded folders
balooctl6 config

# Check baloo status
balooctl6 status

# Monitor temps (should drop significantly)
watch -n 2 sensors
```

### Results
- CPU temp: 85°C → 49-57°C
- CPU fan: 3400 RPM → 1500 RPM
- GPU fan: 3000 RPM → 1200 RPM

### Rollback
```bash
balooctl6 config remove excludeFolders /run/media/
```

---

## Step 9: Install ananicy-cpp (MEDIUM)

**Purpose:** Auto-prioritize processes for desktop responsiveness

### Background
ananicy-cpp automatically adjusts process nice levels:
- Browsers get normal priority
- Games/media get elevated priority
- Background tasks get lower priority

### Apply Fix
```bash
# Install ananicy-cpp
paru -S ananicy-cpp

# Enable and start
sudo systemctl enable --now ananicy-cpp
```

### Verification
```bash
# Check service status
systemctl is-active ananicy-cpp

# Check package installed
pacman -Q ananicy-cpp
```

### Rollback
```bash
sudo systemctl disable --now ananicy-cpp
sudo pacman -R ananicy-cpp
```

---

## Step 10: MAKEFLAGS for AUR Builds (LOW)

**Purpose:** Use all CPU threads for compiling AUR packages

### Background
Default AUR builds use single-threaded compilation.
With 20 threads available, parallel builds are much faster.

### Apply Fix
```bash
# Create user makepkg config
mkdir -p ~/.config/pacman
echo 'MAKEFLAGS="-j$(nproc)"' > ~/.config/pacman/makepkg.conf
```

### Verification
```bash
cat ~/.config/pacman/makepkg.conf
# Should show: MAKEFLAGS="-j$(nproc)"
```

### Rollback
```bash
rm ~/.config/pacman/makepkg.conf
```

---

## NOT FIXING (Intentional)

| Issue | Reason |
|-------|--------|
| DDR5 Memory temp | Hardware limitation, clean vents |
| High memory usage | User workload (3 browsers) |
| No disk encryption | Requires reinstall |
| Battery health 77.9% | Normal wear |
| Bluetooth blocked | User choice |

---

## Execution Checklist

- [x] Step 1: Run btrfs scrub ✅ Completed - no errors found
- [x] Step 2: Apply Samba fix ✅ Bound to 127.0.0.1 + 192.168.1.5 (verified)
- [x] Step 3: Create spd5118 blacklist file ✅ Not loaded (verified)
- [x] Step 4: Edit GRUB (nvidia params + timeout) ✅
- [x] Step 4: Regenerate GRUB config ✅
- [x] **REBOOT** ✅ Completed
- [x] Verify: spd5118 not loaded ✅ `lsmod | grep spd5118` = empty
- [x] Verify: nvidia params ✅ `nvidia_drm.modeset=1 nvidia_drm.fbdev=1`
- [x] Verify: GRUB timeout is 2s ✅
- [x] Step 6: Edit pacman.conf ✅ ParallelDownloads = 10
- [x] Step 7: Disable mullvad-daemon ✅
- [x] Step 8: Baloo exclude /run/media/ ✅ (biggest impact - temps dropped 20°C!)
- [x] Step 9: Install ananicy-cpp ✅ (process auto-prioritizer)
- [x] Step 10: MAKEFLAGS for AUR builds ✅ (20 parallel threads)

### Framebuffer Status
- KWin still shows 139 framebuffer messages (GL_FRAMEBUFFER_INCOMPLETE errors)
- This is a known KDE bug (491751) in hybrid GPU setups
- System is stable - these are non-critical OpenGL warnings
- May improve with future KDE/Mesa updates

---

## Post-Fix Health Check

Run after all fixes applied:

```bash
echo "=== BTRFS ===" && sudo btrfs device stats /
echo "=== SAMBA ===" && ss -tlnp | grep -E "139|445"
echo "=== SPD5118 ===" && lsmod | grep spd5118 || echo "Not loaded (good)"
echo "=== NVIDIA ===" && cat /proc/cmdline | grep nvidia
echo "=== FRAMEBUFFER ERRORS ===" && journalctl -b | grep -c "framebuffer"
echo "=== PACMAN ===" && grep ParallelDownloads /etc/pacman.conf
echo "=== DAEMONS ===" && systemctl list-units --type=service --state=running | wc -l
```

---

## Emergency Recovery

If system won't boot after GRUB changes:

1. At GRUB menu, press `e` to edit
2. Remove `nvidia_drm.modeset=1 nvidia_drm.fbdev=1` from linux line
3. Press `Ctrl+X` to boot
4. Once booted, restore backup:
   ```bash
   sudo cp /etc/default/grub.backup /etc/default/grub
   sudo grub-mkconfig -o /boot/grub/grub.cfg
   ```
