# System State Documentation - FROZEN 2024-12-30

## Hardware Profile

```
Machine:    ASUS TUF Gaming F15
CPU:        12th Gen Intel Core i7-12700H (14 cores, 20 threads)
GPU:        NVIDIA GeForce RTX 3070 Laptop + Intel Integrated
RAM:        32GB DDR5
Display:    3x monitors (eDP-2 internal + DP-1 + HDMI-A-1)
OS:         Garuda Linux (Arch-based)
Kernel:     6.18.2-zen2-1-zen
Desktop:    KDE Plasma 6 (Wayland)
```

---

## Critical Configuration Files

### 1. /etc/environment

```bash
KWIN_DRM_NO_DIRECT_SCANOUT=1
```

**WHY THIS SETTING:**
- Prevents KWin from using direct scanout optimization
- Fixes framebuffer errors with multi-monitor setups on NVIDIA
- Required for stable compositing with hybrid Intel/NVIDIA GPUs

**DO NOT ADD:**
- `KWIN_DRM_DEVICES` - Breaks internal display when set to NVIDIA only
- `__GL_GSYNC_ALLOWED` - Can cause flickering with multiple monitors

---

### 2. ~/.config/environment.d/kwin-fixes.conf

```bash
# Disable DDC brightness control - prevents display crashes on hybrid GPU
# Crash signature: org_kde_powerdevil "No Display_Ref found for i2c bus"
# DDC also disabled per-monitor in kwinoutputconfig.json (allowDdcCi=false)
POWERDEVIL_NO_DDCUTIL=1
```

**WHY THIS SETTING:**
- Disables PowerDevil DDC brightness control
- DDC is also disabled per-monitor in kwinoutputconfig.json
- This prevents display server crashes from i2c bus access

**DO NOT ADD:**
- `KWIN_DRM_NO_AMS=1` - Forces legacy mode, causes 40%+ KWin CPU and cursor lag on external monitors

**PREVIOUS ISSUE (FIXED 2025-12-30):**
- `KWIN_DRM_NO_AMS=1` was causing cursor lag on external monitors
- Removed because DDC protection is now handled by per-monitor `allowDdcCi=false`

---

### 3. ~/.config/kwinrc

```ini
[Plugins]
blurEnabled=false
forceblurEnabled=false
kwin4_effect_shapecornersEnabled=false
coverswitchEnabled=true
desktopchangeosdEnabled=true
fadeEnabled=true
flipswitchEnabled=true
magiclampEnabled=true
sheetEnabled=true
wobblywindowsEnabled=false

[Effect-blurplus]
BlurDecorations=true
BlurMatching=false
BlurNonMatching=true
BlurStrength=10
TopCornerRadius=20
BottomCornerRadius=20
DockCornerRadius=20
MenuCornerRadius=20
NoiseStrength=0
PaintAsTranslucent=true
WindowClasses=xwaylandvideobridge

[Windows]
BorderlessMaximizedWindows=true
Placement=Random

[Xwayland]
Scale=1.5
```

**WHY THESE SETTINGS:**

| Setting | Value | Reason |
|---------|-------|--------|
| `blurEnabled` | false | Native blur causes 50%+ CPU on KWin with 3 monitors at 165Hz |
| `forceblurEnabled` | false | Third-party blur effect, extremely CPU intensive |
| `kwin4_effect_shapecornersEnabled` | false | Causes high CPU usage per-window |
| `coverswitchEnabled` | true | Low-cost visual effect for Alt+Tab |
| `fadeEnabled` | true | Minimal CPU impact, nice UX |
| `magiclampEnabled` | true | Minimize animation, low CPU cost |
| `Xwayland Scale` | 1.5 | Matches display scale for X11 apps |

**SAFE TO ENABLE (low CPU cost):**
- coverswitch, flipswitch, fade, sheet, magiclamp, desktopchangeosd

**DO NOT ENABLE (high CPU cost):**
- blur, forceblur, shapecorners, wobblywindows, cube

---

### 4. ~/.config/kwinoutputconfig.json

```json
{
  "connectorName": "eDP-2",
  "allowDdcCi": false,
  "vrrPolicy": "Never",
  "scale": 1.5,
  "mode": { "width": 2560, "height": 1440, "refreshRate": 165003 }
},
{
  "connectorName": "DP-1",
  "allowDdcCi": false,
  "vrrPolicy": "Never",
  "scale": 1.25
},
{
  "connectorName": "HDMI-A-1",
  "allowDdcCi": false,
  "vrrPolicy": "Never",
  "scale": 1.25
}
```

**WHY THESE SETTINGS:**

| Setting | Value | Reason |
|---------|-------|--------|
| `allowDdcCi` | false | DDC/CI causes NVIDIA I2C transfer errors and screen flickering |
| `vrrPolicy` | Never | VRR/FreeSync can cause stuttering with multi-monitor setups |
| `scale` | 1.5/1.25 | Optimal readability for 2560x1440 displays |

**DO NOT CHANGE:**
- `allowDdcCi` to true - Will cause flickering and kernel errors
- `vrrPolicy` to Always - Inconsistent refresh rates cause stuttering

**HOW TO DISABLE DDC/CI:**
System Settings → Display & Monitor → Display Configuration → Click monitor → Uncheck "Control hardware brightness with DDC/CI"

This setting persists across logout/login when changed via GUI.

---

### 5. ~/.config/kwinrulesrc

```ini
[7671702b-3c52-4446-82dd-0443b286620c]
Description=Chromium opacity
opacityactiverule=2
opacityinactiverule=2
types=1
wmclass=chromium
wmclasscomplete=true
wmclassmatch=2

[09949acb-65a8-4b03-ab55-b8915fd004f3]
Description=Blender opacity
opacityactiverule=2
opacityinactiverule=2
types=1
wmclass=blender
wmclasscomplete=true
wmclassmatch=2

[General]
count=2
rules=7671702b-3c52-4446-82dd-0443b286620c,09949acb-65a8-4b03-ab55-b8915fd004f3
```

**WHY THESE SETTINGS:**
- Per-application opacity rules instead of global rules
- `opacityactiverule=2` / `opacityinactiverule=2` = "Do not affect" (default opacity)
- Prevents compositor from doing unnecessary transparency calculations

**REMOVED:**
- Global 90% opacity rule that was causing extra compositing overhead

---

### 6. ~/.config/environment.d/firefox.conf

```bash
MOZ_USE_XINPUT2=1
```

**WHY THIS SETTING:**
- Enables smooth touchpad scrolling in Firefox
- Required for proper input handling under Wayland/XWayland

**SYNTAX NOTE:**
- Must be `KEY=VALUE` format only
- NOT `env KEY=VALUE command` (that's shell syntax, not environment.d syntax)

---

## Power Management Stack

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    asusctl                          │
│  (ASUS laptop control: fans, profiles, LEDs)        │
├─────────────────────────────────────────────────────┤
│              power-profiles-daemon                  │
│  (D-Bus interface for power profiles)               │
├─────────────────────────────────────────────────────┤
│                  intel_pstate                       │
│  (CPU frequency scaling driver)                     │
├─────────────────────────────────────────────────────┤
│     Energy Performance Preference (EPP)             │
│  (Hardware-level power/performance hint)            │
└─────────────────────────────────────────────────────┘
```

### Profile Mappings

| asusctl Profile | power-profiles-daemon | EPP Setting | Use Case |
|-----------------|----------------------|-------------|----------|
| Quiet | power-saver | power | Battery, quiet work |
| **Balanced** | balanced | **balance_power** | **Daily use (DEFAULT)** |
| Performance | performance | performance | Gaming, compiling |

### Current Settings

```bash
# CPU Governor (DO NOT CHANGE)
/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor = powersave
/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver = intel_pstate

# Energy Performance Preference
/sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference = balance_power
```

**WHY powersave GOVERNOR:**
- With `intel_pstate` driver, "powersave" is DYNAMIC (not fixed low frequency)
- The governor allows CPU to scale from minimum to maximum based on load
- EPP (balance_power) controls the bias toward power saving vs performance
- This is fundamentally different from generic cpufreq "powersave"

**DO NOT:**
- Set governor to "performance" manually (wastes power, adds heat)
- Install schedutil (doesn't work with intel_pstate)
- Add systemd services to override governors (breaks asusctl integration)

### Profile on AC/Battery

```
Active profile is Balanced
Profile on AC is Balanced      # Changed 2025-12-30 (was Performance)
Profile on Battery is Quiet
```

**WHY Balanced on AC:**
- Prioritizes cooling over silence
- Fans at 0 RPM when idle/cool, ramp up when needed
- Performance profile too aggressive (constant 2500+ RPM)
- Quiet profile risks throttling under load

### Custom Fan Curves

```bash
# Check current curves
asusctl fan-curve -m Balanced
```

**Status:** Default (disabled) - BIOS controls fans

**Note:** Custom fan curves were tested but CPU fan doesn't respond properly on this TUF model (firmware limitation). GPU fan curve works. Left at default for reliable cooling.

### Commands

```bash
# Check current profile
asusctl profile -p

# Switch profiles
asusctl profile -P Balanced    # Daily use
asusctl profile -P Performance # Heavy workloads
asusctl profile -P Quiet       # Silent/battery

# Set AC/Battery defaults
asusctl profile -a Balanced    # AC power profile
asusctl profile -b Quiet       # Battery profile

# Verify CPU state
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
```

---

## Memory & Swap Configuration

### Current Settings

```bash
vm.swappiness = 133
vm.vfs_cache_pressure = 100
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
```

### ZRAM Configuration

```
NAME       ALGORITHM DISKSIZE DATA COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram0 zstd      31G      ...  ...   ...   ...     [SWAP]
```

**WHY swappiness=133:**
- Garuda-specific optimization for ZRAM
- Values >100 tell kernel to PREFER zram over keeping pages in RAM
- ZRAM is compressed RAM, so this is beneficial:
  - Faster than disk swap
  - Compresses inactive pages
  - Keeps more RAM free for file cache

**DO NOT CHANGE:**
- `vm.swappiness` to lower values - defeats purpose of zram
- ZRAM algorithm from zstd - best compression ratio

---

## Critical System Services

### Enabled Services

| Service | Purpose | Status |
|---------|---------|--------|
| `power-profiles-daemon` | Power profile management | Required |
| `asusd` | ASUS laptop control | Required for TUF |
| `ananicy-cpp` | Process priority optimization | Recommended |
| `NetworkManager` | Network management | Required |
| `bluetooth` | Bluetooth support | Optional |

### Service Commands

```bash
# Check service status
systemctl status power-profiles-daemon asusd ananicy-cpp

# Restart if issues
sudo systemctl restart asusd
sudo systemctl restart power-profiles-daemon
```

---

## GPU Configuration

### Driver Stack

```
NVIDIA Driver: proprietary (nvidia-dkms)
Intel Driver: i915 (kernel module)
DRM Devices:
  /dev/dri/card1 = NVIDIA RTX 3070
  /dev/dri/card2 = Intel integrated
```

### Render Offload

KWin uses Intel for display composition, NVIDIA for rendering when needed.

**WHY NOT force NVIDIA for everything:**
- NVIDIA cannot drive the internal eDP display directly
- Hybrid setup is required for laptop displays
- Setting `KWIN_DRM_DEVICES=/dev/dri/card1` breaks internal monitor

### NVIDIA Power States

| State | Power | Description |
|-------|-------|-------------|
| P0 | Max | Full performance |
| P2 | High | Gaming/heavy work |
| P3 | Medium | Light GPU work |
| P5 | Low | Idle (current baseline) |
| P8 | Minimal | Deep idle |

```bash
# Check GPU state
nvidia-smi --query-gpu=pstate,power.draw --format=csv
```

---

## I/O Configuration

### Scheduler

```bash
/sys/block/nvme0n1/queue/scheduler = [kyber]
```

**WHY kyber:**
- Optimized for NVMe SSDs
- Low latency, good throughput
- Better than mq-deadline for desktop use

---

## Troubleshooting Guide

### Problem: KWin high CPU (>50%)

**Check:**
```bash
ps aux | grep kwin
```

**Fix:**
1. Disable blur effects in System Settings > Desktop Effects
2. Verify kwinrc has `blurEnabled=false`
3. Log out/in

### Problem: Screen flickering

**Check:**
```bash
journalctl -b | grep -i "i2c\|ddc"
```

**Fix:**
1. Ensure `allowDdcCi=false` in kwinoutputconfig.json
2. Log out/in

### Problem: Mouse lag

**Check:**
```bash
asusctl profile -p
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
```

**Fix:**
1. If profile is "Quiet" or EPP is "power", switch to Balanced:
   ```bash
   asusctl profile -P Balanced
   ```

### Problem: Internal display not working

**Check:**
```bash
cat /etc/environment | grep KWIN_DRM_DEVICES
```

**Fix:**
1. Remove any `KWIN_DRM_DEVICES` line from /etc/environment
2. Reboot

### Problem: Inkscape/GTK apps slow

**Fix:**
1. Reset app config:
   ```bash
   mv ~/.config/inkscape ~/.config/inkscape.backup
   ```
2. Restart app

### Problem: GPU stuck in high power state

**Check:**
```bash
nvidia-smi
```

**Fix:**
```bash
# Kill any processes using GPU
nvidia-smi --query-compute-apps=pid --format=csv,noheader | xargs -r kill

# Or reboot
```

---

## Maintenance Commands

### Weekly

```bash
# Clean package cache (keep 2 versions)
sudo paccache -rk2

# Check for orphan packages
pacman -Qdt

# Update system
paru -Syu
```

### After Major Updates

```bash
# Verify services still running
systemctl status power-profiles-daemon asusd ananicy-cpp

# Check KWin CPU
ps aux | grep kwin

# Verify GPU state
nvidia-smi --query-gpu=pstate,power.draw --format=csv
```

---

## Configuration Backup Locations

These files should be backed up:

```
/etc/environment
~/.config/kwinrc
~/.config/kwinoutputconfig.json
~/.config/kwinrulesrc
~/.config/environment.d/firefox.conf
```

---

## Version History

| Date | Change | Reason |
|------|--------|--------|
| 2024-12-30 | Initial frozen state | System stability achieved |
| 2024-12-30 | Disabled DDC/CI | Fixed screen flickering |
| 2024-12-30 | Disabled blur effects | Reduced KWin CPU from 80%+ to ~20% |
| 2024-12-30 | Removed KWIN_DRM_DEVICES | Fixed internal display |
| 2024-12-30 | Reset Inkscape config | Fixed GTK app lag |
| 2025-12-30 | Removed KWIN_DRM_NO_AMS=1 | Fixed cursor lag on external monitors (40% KWin CPU → ~10%) |
| 2025-12-30 | Changed AC profile to Balanced | Cooling priority; fans 0 RPM idle, ramp when needed |
| 2025-12-30 | Removed conky packages | Not in use, was autostarting unnecessarily |
| 2025-12-30 | Disabled DDC via GUI | System Settings toggle persists; no script hack needed |

---

## DO NOT TOUCH Summary

| Setting | Location | Risk if Changed |
|---------|----------|-----------------|
| `blurEnabled=false` | kwinrc | High CPU, system lag |
| `allowDdcCi=false` | kwinoutputconfig.json | Screen flickering, cursor lag |
| `KWIN_DRM_DEVICES` | /etc/environment | Internal display breaks |
| `vm.swappiness=133` | sysctl | ZRAM inefficiency |
| CPU governor | sysctl/systemd | Breaks asusctl integration |

## DO NOT ADD

| Setting | Location | Risk if Added |
|---------|----------|---------------|
| `KWIN_DRM_NO_AMS=1` | environment.d | Forces legacy mode, 40%+ KWin CPU, cursor lag |
