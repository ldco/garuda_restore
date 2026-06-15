# Sleep/Wake Fix History — Complete Record

**Created:** 2026-03-08  
**System:** ASUS TUF Gaming F15 FX507ZR  
**OS:** Garuda Linux (KDE Plasma 6.5.4, Wayland)  
**Hardware:** Intel i7-12700H + NVIDIA RTX 3070 Mobile (hybrid GPU)

---

## Problem Statement

### Primary Issue: Login Button Freeze After Sleep

**Symptoms:**
- System wakes from sleep normally
- Login screen (SDDM/lockscreen) renders correctly
- Password field accepts input
- **Login button does nothing when clicked**
- Switching user also does nothing
- Keyboard shortcuts may still respond
- **Only hard reboot recovers the system**
- TTY switching (Ctrl+Alt+F3) does NOT work during freeze

### Root Cause (Per Analysis)

Wayland compositor (KWin) fails to restore GPU context after suspend:

1. systemd restores user session
2. SDDM launches Wayland session
3. KWin Wayland fails to restore GPU context
4. Lockscreen UI renders but is **disconnected from session backend**
5. Authentication events cannot reach compositor session
6. Login button appears frozen

---

## Current System State (2026-03-08)

### Installed Sleep Hooks

| Hook | Location | Status | Purpose |
|------|----------|--------|---------|
| SDDM Input Reset | `/etc/systemd/system-sleep/sddm-input-reset` | ✅ Installed | Re-probes input devices after wake |
| KWin Compositor Fix | `/etc/systemd/system-sleep/99-kwin-fix` | ❌ NOT Installed | Restarts KWin compositor after wake |

### GRUB Configuration

```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1'
```

**Status:** ✅ Clean — no risky parameters

**NOT present (removed/never added):**
- `nvidia_drm.fbdev=1` — causes thermal instability
- `mem_sleep_default=deep` — causes KWin atomic modeset failures
- `mem_sleep_default=s2idle` — redundant (already default)

### Sleep Mode

```bash
$ cat /sys/power/mem_sleep
[s2idle] deep
```

**Status:** ✅ s2idle (system default)

### NVIDIA Services

| Service | Status | Purpose |
|---------|--------|---------|
| `nvidia-suspend.service` | ✅ Enabled (inactive) | NVIDIA GPU suspend handling |
| `nvidia-resume.service` | ✅ Enabled (inactive) | NVIDIA GPU resume handling |
| `nvidia-hibernate.service` | ✅ Enabled (inactive) | NVIDIA GPU hibernate handling |

**Note:** Services are enabled but show "inactive" because they're triggered only during suspend/hibernate events — this is normal.

### Lock Screen Settings

| Setting | Current Value | Notes |
|---------|---------------|-------|
| Lock automatically | ✅ `true` (ENABLED) | Good for security |
| Lock after waking from sleep | ⚠️ Not explicitly set | May default to enabled |

**Status:** Lock screen is ENABLED — good for security. Fixes should make it work properly.

---

## Fixes Applied (Historical Record)

### 2025-12-29 — Initial System Optimization

#### GRUB NVIDIA Parameters
**What:** Added `nvidia_drm.modeset=1 nvidia_drm.fbdev=1` to GRUB  
**Why:** Enable NVIDIA framebuffer for KWin hybrid GPU support  
**Result:** ❌ **FAILED** — caused thermal instability (GPU stuck at 40W, system overheating to 96°C)  
**Rollback:**
```bash
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

#### GPU Rendering Order
**What:** Set `KWIN_DRM_DEVICES=/dev/dri/card1:/dev/dri/card2` (NVIDIA first)  
**Why:** Attempted to fix rendering issues  
**Result:** ❌ **FAILED** — caused all apps to render on NVIDIA, 65W idle draw, fans at 3300/3000 RPM  
**Rollback:** Removed from `/etc/environment`

#### Baloo Exclude External Drives
**What:** Added `/run/media/` to Baloo exclude folders  
**Why:** Stop Baloo from indexing 2M+ files causing CPU at 85-92°C  
**Result:** ✅ **SUCCESS** — biggest temperature improvement  
**Status:** Still active

#### Blacklist spd5118 DDR5 Sensor
**What:** Created `/etc/modprobe.d/blacklist-spd5118.conf`  
**Why:** Stop DDR5 sensor driver causing resume errors  
**Result:** ✅ **SUCCESS** — module not loaded  
**Status:** Still active

#### Samba Security Hardening
**What:** Bound Samba to local interfaces only  
**Why:** Security — prevent listening on 0.0.0.0:445  
**Result:** ✅ **SUCCESS**  
**Status:** Still active

---

### 2025-12-30 — Thermal Stability Fixes

#### Remove nvidia_drm.fbdev=1
**What:** Removed from GRUB parameters  
**Why:** GPU stuck at 40W idle, system overheating  
**Result:** ✅ **SUCCESS** — NVIDIA can sleep, fans drop to 1500/1200 RPM  
**Status:** Still active (parameter not re-added)

#### GPU Rendering Order Fix
**What:** Changed to Intel first (or removed entirely)  
**Why:** NVIDIA-first caused high power draw  
**Result:** ✅ **SUCCESS** — internal display works, power normal  
**Status:** `KWIN_DRM_DEVICES` NOT set (system default)

#### Cursor Lag Fix — Remove KWIN_DRM_NO_AMS=1
**What:** Removed `KWIN_DRM_NO_AMS=1` from `~/.config/environment.d/kwin-fixes.conf`  
**Why:** Forcing legacy mode caused 40%+ KWin CPU, cursor lag on external monitors  
**Result:** ✅ **SUCCESS** — KWin CPU ~10%, cursor smooth  
**Status:** Still active (not re-added)

#### DDC/CI Disabled Per-Monitor
**What:** Set `allowDdcCi=false` in `~/.config/kwinoutputconfig.json` for all monitors  
**Why:** DDC/CI causes NVIDIA I2C transfer errors, screen flickering  
**Result:** ✅ **SUCCESS** — no flickering, no I2C errors  
**Status:** Still active

#### Power Profile: Balanced on AC
**What:** `asusctl profile -a Balanced` (changed from Performance)  
**Why:** Performance profile caused constant 2500+ RPM fans  
**Result:** ✅ **SUCCESS** — fans at 0 RPM idle, ramp when needed  
**Status:** Still active

#### Remove Conky
**What:** Removed conky packages and autostart  
**Why:** Not in use, was autostarting unnecessarily  
**Result:** ✅ **SUCCESS** — cleaner system  
**Status:** Still removed

---

### 2026-03-07/08 — Sleep/Wake Specific Fixes

#### SDDM Input Reset Hook
**What:** Installed `/etc/systemd/system-sleep/sddm-input-reset`  
**Why:** Fix login screen not accepting keyboard/mouse input after wake  
**Script:** `scripts/fix-sddm-input.sh`  
**What it does:**
- Re-probes input devices via udevadm trigger (safe, no module unload)
- Enables wakeup for suspended input devices
- Runs SDDM health checks (process, greeter, D-Bus)
- Performs bounded SDDM restart if health checks fail
- Session-aware: skips restart if user session active

**Result:** ⚠️ **PARTIAL** — fixes input device wake, but does NOT fix KWin compositor freeze  
**Status:** ✅ Installed

#### KWin Compositor Fix
**What:** NOT YET APPLIED  
**Why:** Fix post-login freeze after sleep (desktop freezes after login)  
**Script:** `scripts/fix-sleep-kwin.sh`  
**What it should do:**
- Reset Intel backlight after wake
- Force DRM/display reprobe
- Restart KWin compositor via D-Bus
- Log GPU power state

**Result:** ⏳ **NOT TESTED** — needs to be applied  
**Status:** ❌ NOT Installed

---

## Fixes NOT Yet Applied (Pending)

### 1. KWin Compositor Fix (HIGH PRIORITY)

**Script:** `scripts/fix-sleep-kwin.sh`  
**Location:** Should install to `/etc/systemd/system-sleep/99-kwin-fix`  
**Purpose:** Restart KWin compositor after wake to prevent freeze

**Apply command:**
```bash
sudo /run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb/LinuxDCO/garuda-restore/scripts/fix-sleep-kwin.sh
```

**Why needed:** Current symptom is **post-login freeze**, which SDDM fix doesn't address

---

### 2. NVIDIA Suspend Services (DONE - Already Enabled)

**Status:** ✅ Already enabled

```bash
$ systemctl status nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
  ○ nvidia-suspend.service - Loaded: enabled
  ○ nvidia-resume.service - Loaded: enabled
  ○ nvidia-hibernate.service - Loaded: enabled
```

**Note:** Services show "inactive" because they're triggered only during suspend/hibernate events — this is normal behavior.

---

### 3. Lock Screen Settings Verification (LOW PRIORITY)

**Check:**
```
System Settings → Workspace Behavior → Screen Locking
```

**Verify:**
- Lock automatically: should be ENABLED (for security)
- Lock after waking from sleep: should be ENABLED (for security)

**Note:** Disabling these is a workaround, not a fix. If KWin fix works, lock screen should work.

---

## Rollback Commands (If Fixes Cause Issues)

### Remove SDDM Input Fix
```bash
sudo rm -f /etc/systemd/system-sleep/sddm-input-reset
sudo udevadm control --reload-rules
```

### Remove KWin Fix (if applied)
```bash
sudo rm -f /etc/systemd/system-sleep/99-kwin-fix
sudo udevadm control --reload-rules
```

### Remove NVIDIA Suspend Services
```bash
sudo systemctl disable nvidia-suspend.service
sudo systemctl disable nvidia-resume.service
sudo systemctl disable nvidia-hibernate.service
```

### Rollback GRUB Changes
```bash
# If any risky parameters were added:
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub
sudo sed -i 's/mem_sleep_default=deep //' /etc/default/grub
sudo sed -i 's/mem_sleep_default=s2idle //' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

### Rollback Environment Variables
```bash
# Remove KWIN_DRM_DEVICES if added:
sudo sed -i '/KWIN_DRM_DEVICES/d' /etc/environment

# Remove KWIN_DRM_NO_AMS if added:
rm -f ~/.config/environment.d/kwin-fixes.conf
```

### Rollback KWin Output Config
```bash
# Edit ~/.config/kwinoutputconfig.json
# Set "allowDdcCi": true for all monitors
# Set "vrrPolicy": "Always" or "Automatic"
```

---

## Diagnostic Commands

### Check Current State
```bash
# Sleep mode
cat /sys/power/mem_sleep

# GRUB parameters
cat /etc/default/grub | grep GRUB_CMDLINE

# Installed sleep hooks
ls -la /etc/systemd/system-sleep/

# NVIDIA services status
systemctl status nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service

# KWin CPU usage
ps aux | grep kwin

# GPU power state
nvidia-smi --query-gpu=pstate,power.draw --format=csv
```

### Test Sleep
```bash
# Trigger sleep
systemctl suspend

# After wake, check logs
tail /var/log/kwin-sleep.log        # KWin fix logs (if installed)
tail /var/log/sddm-input-reset.log  # SDDM fix logs

# Check KWin is running
ps aux | grep kwin_wayland

# Check session state
loginctl list-sessions
```

### Check Lock Screen Settings
```bash
# Check kscreenlocker config
kreadconfig6 --file kscreenlockerrc --group Daemon --key Autolock
kreadconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume
```

---

## Test Matrix (After Each Fix Applied)

| Test | Expected Result | Actual Result | Pass/Fail |
|------|-----------------|---------------|-----------|
| `systemctl suspend` | System sleeps | ❓ | ⏳ |
| Wake with lid open | System wakes, lockscreen appears | ❓ | ⏳ |
| Type password | Password field accepts input | ❓ | ⏳ |
| Click login button | Session starts, desktop appears | ❓ | ⏳ |
| TTY switch during freeze | Ctrl+Alt+F3 works | ❓ | ⏳ |
| KWin log shows restart | "KWin restart SUCCESS" in logs | ❓ | ⏳ |

---

## Known Issues That Are NOT Sleep-Related

### Thermal Instability from GRUB Parameters
**Parameters:** `nvidia_drm.fbdev=1`, `mem_sleep_default=deep`  
**Symptoms:** GPU stuck at 40W, system overheating to 96°C, thermal shutdown  
**Status:** ✅ Resolved — parameters removed from GRUB

### Cursor Lag on External Monitors
**Cause:** `KWIN_DRM_NO_AMS=1` forcing legacy mode  
**Symptoms:** 40%+ KWin CPU, cursor lag on DP/HDMI, smooth on eDP  
**Status:** ✅ Resolved — parameter removed

### Screen Flickering
**Cause:** DDC/CI enabled on monitors  
**Symptoms:** NVIDIA I2C transfer errors, screen flickering  
**Status:** ✅ Resolved — `allowDdcCi=false` set per-monitor

---

## Next Steps (If Issue Persists After KWin Fix)

### Step 1: Verify KWin Fix Applied Correctly
```bash
# Check hook exists
ls -la /etc/systemd/system-sleep/99-kwin-fix

# Check log after sleep
tail /var/log/kwin-sleep.log

# Should show:
# === RESUME ===
# Backlight reset: ...
# DRM triggered
# KWin restart SUCCESS for <user>
# === RESUME COMPLETE ===
```

### Step 2: Enable NVIDIA Suspend Services
```bash
sudo systemctl enable nvidia-suspend.service
sudo systemctl enable nvidia-resume.service
sudo systemctl enable nvidia-hibernate.service
sudo reboot
```

### Step 3: Check for KWin/Plasma Updates
```bash
sudo pacman -Syu plasma-workspace kwin kscreenlocker
```

### Step 4: Collect Debug Logs
```bash
# Full sleep/wake log
journalctl -b | grep -iE "suspend|resume|kwin|sddm|nvidia" > /tmp/sleep-debug.log

# KWin specific
journalctl -b | grep kwin > /tmp/kwin-debug.log

# SDDM specific
journalctl -b | grep sddm > /tmp/sddm-debug.log
```

### Step 5: Try X11 Session (Temporary Workaround)
At SDDM login screen:
- Click session type
- Select "Plasma (X11)" instead of "Plasma (Wayland)"
- Test sleep/wake

If X11 works but Wayland doesn't, it's a Wayland-specific bug.

### Step 6: Report Upstream
If all fixes fail:
- KDE Bug: https://bugs.kde.org/
- Include logs from Step 4
- Reference existing bugs:
  - [KDE Bug 491751](https://bugs.kde.org/show_bug.cgi?id=491751) — Framebuffer errors
  - [KDE Bug 477738](https://bugs.kde.org/show_bug.cgi?id=477738) — Black screen after resume

---

## Files Modified (Current State)

| File | Current Content | Modified |
|------|-----------------|----------|
| `/etc/default/grub` | `quiet loglevel=3 nvidia_drm.modeset=1` | 2025-12-30 |
| `/etc/environment` | `KWIN_DRM_NO_DIRECT_SCANOUT=1` | 2025-12-30 |
| `~/.config/environment.d/kwin-fixes.conf` | `POWERDEVIL_NO_DDCUTIL=1` | 2025-12-30 |
| `~/.config/kwinrc` | blur disabled, etc. | 2025-12-30 |
| `~/.config/kwinoutputconfig.json` | `allowDdcCi=false` all monitors | 2025-12-30 |
| `/etc/modprobe.d/blacklist-spd5118.conf` | `blacklist spd5118` | 2025-12-29 |
| `/etc/systemd/system-sleep/sddm-input-reset` | Input reprobe hook | 2026-03-07 |
| `/etc/systemd/system-sleep/99-kwin-fix` | ❌ NOT PRESENT | ⏳ Pending |

---

## Summary

### What Works
- ✅ SDDM input device wake (keyboard/mouse work at login screen)
- ✅ NVIDIA suspend/resume services (enabled)
- ✅ Thermal stability (no more 96°C overheating)
- ✅ Cursor smooth on all monitors
- ✅ No screen flickering
- ✅ Balanced power profile (quiet fans at idle)
- ✅ Lock screen enabled (for security)

### What Doesn't Work (Yet)
- ❌ **Post-login freeze after sleep** (desktop freezes after clicking login)
- ❌ KWin compositor fix not yet applied

### Next Action Required
```bash
# Apply KWin compositor fix (THIS IS THE KEY FIX)
sudo /run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb/LinuxDCO/garuda-restore/scripts/fix-sleep-kwin.sh

# Test
systemctl suspend
# Wake → login → desktop should work
```

**If the issue persists after applying the KWin fix**, see "Next Steps (If Issue Persists After KWin Fix)" section for advanced debugging.

---

**Document Version:** 1.0  
**Last Updated:** 2026-03-08  
**Maintained By:** Garuda Restore Project
