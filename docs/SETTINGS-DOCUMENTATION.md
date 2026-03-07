# Settings Documentation — Garuda Restore Kit

Every setting applied by the restore kit is documented below with its purpose, conditions, and rollback procedure.

---

## Table of Contents

1. [Kernel Parameters (GRUB)](#1-kernel-parameters-grub)
2. [Environment Variables](#2-environment-variables)
3. [KWin Compositor Settings](#3-kwin-compositor-settings)
4. [Power Management](#4-power-management)
5. [Memory & Swap](#5-memory--swap)
6. [I/O Scheduler](#6-io-scheduler)
7. [System Services](#7-system-services)
8. [Security Settings](#8-security-settings)

---

## 1. Kernel Parameters (GRUB)

### nvidia_drm.modeset=1

**Location:** `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`

**Applied when:** NVIDIA GPU detected

**Why:** Enables DRM (Direct Rendering Manager) kernel mode setting for NVIDIA GPUs. Required for:
- Wayland session support
- Proper sleep/wake behavior
- Display hotplug detection
- NVIDIA Prime offloading

**Safe to remove?** No — breaks Wayland and sleep on NVIDIA systems.

**Rollback:**
```bash
sudo sed -i 's/ nvidia_drm.modeset=1//' /etc/default/grub
sudo update-grub
```

---

### nvidia_drm.fbdev=1

**Location:** `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`

**Applied when:** NVIDIA GPU + internal display issues detected

**Why:** Forces NVIDIA DRM to use framebuffer device. Helps with:
- Laptop internal displays not detected
- Brightness control issues
- Display initialization problems

**Safe to remove?** Yes — only needed if internal display doesn't work with modeset alone.

**Rollback:**
```bash
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub
sudo update-grub
```

---

### quiet loglevel=3

**Location:** `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`

**Applied when:** Always (universal)

**Why:** Reduces boot message verbosity:
- `quiet` — Suppresses most boot messages
- `loglevel=3` — Shows only errors and warnings in dmesg

**Safe to remove?** Yes — only affects boot message verbosity.

**Rollback:**
```bash
sudo sed -i 's/quiet loglevel=3/quiet/' /etc/default/grub
sudo update-grub
```

---

### amdgpu.sg_display=0

**Location:** `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`

**Applied when:** AMD GPU detected (not APU)

**Why:** Disables scatter/gather display optimization on discrete AMD GPUs. Fixes:
- Screen flickering on RX 6000/7000 series
- Display corruption with multiple monitors
- Random black screens

**Safe to remove?** Yes — but may cause flickering on some AMD GPUs.

**Rollback:**
```bash
sudo sed -i 's/ amdgpu.sg_display=0//' /etc/default/grub
sudo update-grub
```

---

### i915.enable_psr=0

**Location:** `/etc/default/grub` → `GRUB_CMDLINE_LINUX_DEFAULT`

**Applied when:** Intel GPU detected

**Why:** Disables Panel Self Refresh (PSR) on Intel integrated graphics. Prevents:
- Screen freezing/stuttering
- Tearing during video playback
- Display corruption on some panels

**Safe to remove?** Yes — PSR is a power-saving feature, not critical.

**Rollback:**
```bash
sudo sed -i 's/ i915.enable_psr=0//' /etc/default/grub
sudo update-grub
```

---

## 2. Environment Variables

### KWIN_DRM_NO_DIRECT_SCANOUT=1

**Location:** `/etc/environment`

**Applied when:** Multi-monitor + NVIDIA GPU

**Why:** Prevents KWin from using direct scanout optimization. Fixes:
- Framebuffer errors in logs (`framebuffer errors`)
- Screen corruption with multiple monitors
- Compositing issues on hybrid GPU systems

**Safe to remove?** Yes — but may cause framebuffer warnings and instability.

**Rollback:**
```bash
sudo sed -i '/KWIN_DRM_NO_DIRECT_SCANOUT/d' /etc/environment
# Logout and login
```

---

### POWERDEVIL_NO_DDCUTIL=1

**Location:** `~/.config/environment.d/kwin-fixes.conf`

**Applied when:** Hybrid GPU (Intel + NVIDIA) detected

**Why:** Disables DDC/CI brightness control in PowerDevil. Prevents:
- Display server crashes with signature: `org_kde_powerdevil "No Display_Ref found for i2c bus"`
- I2C transfer errors on NVIDIA GPUs
- Screen flickering from DDC communication

**Safe to remove?** Yes — but may cause brightness control crashes on hybrid GPU.

**Rollback:**
```bash
rm ~/.config/environment.d/kwin-fixes.conf
# Logout and login
```

---

### MOZ_USE_XINPUT2=1

**Location:** `~/.config/environment.d/firefox.conf`

**Applied when:** Firefox installed

**Why:** Enables XInput2 support in Firefox. Provides:
- Smooth touchpad scrolling
- Proper high-DPI scaling
- Better pointer acceleration

**Safe to remove?** Yes — Firefox will use default input handling.

**Rollback:**
```bash
rm ~/.config/environment.d/firefox.conf
# Restart Firefox
```

---

### MOZ_ENABLE_WAYLAND=1

**Location:** `~/.config/environment.d/garuda.conf`

**Applied when:** Always (universal for Wayland systems)

**Why:** Forces Firefox to use Wayland backend instead of XWayland. Benefits:
- Native Wayland features (fractional scaling, touchpad gestures)
- Better performance
- Proper HiDPI support

**Safe to remove?** Yes — Firefox will run under XWayland.

**Rollback:**
```bash
sed -i '/MOZ_ENABLE_WAYLAND/d' ~/.config/environment.d/garuda.conf
# Restart Firefox
```

---

### GTK_USE_PORTAL=1

**Location:** `~/.config/environment.d/garuda.conf`

**Applied when:** Always (universal)

**Why:** Forces GTK apps to use XDG Desktop Portal. Enables:
- Proper file picker dialogs in sandboxed apps
- Better integration with KDE
- Support for Flatpak/Snap apps

**Safe to remove?** Yes — GTK apps will use native dialogs.

**Rollback:**
```bash
sed -i '/GTK_USE_PORTAL/d' ~/.config/environment.d/garuda.conf
# Restart GTK apps
```

---

## 3. KWin Compositor Settings

### blurEnabled=false

**Location:** `~/.config/kwinrc` → `[Plugins]`

**Applied when:** Always (universal performance optimization)

**Why:** Disables native KWin blur effect. Prevents:
- High CPU usage (50%+ with 3 monitors at 165Hz)
- Compositor lag
- Stuttering during window movements

**Safe to remove?** Yes — but will increase CPU usage significantly.

**Rollback:**
```bash
kwriteconfig5 --file kwinrc --group Plugins --key blurEnabled true
qdbus org.kde.KWin /KWin reconfigure
```

---

### forceblurEnabled=false

**Location:** `~/.config/kwinrc` → `[Plugins]`

**Applied when:** Always (universal performance optimization)

**Why:** Disables third-party blur effect. Even more CPU-intensive than native blur.

**Safe to remove?** Yes — already disabled by default.

**Rollback:**
```bash
kwriteconfig5 --file kwinrc --group Plugins --key forceblurEnabled true
qdbus org.kde.KWin /KWin reconfigure
```

---

### kwin4_effect_shapecornersEnabled=false

**Location:** `~/.config/kwinrc` → `[Plugins]`

**Applied when:** Always (universal performance optimization)

**Why:** Disables shape corners effect. Reduces:
- Per-window compositing overhead
- CPU usage with many windows

**Safe to remove?** Yes — purely visual effect.

**Rollback:**
```bash
kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_shapecornersEnabled true
qdbus org.kde.KWin /KWin reconfigure
```

---

### allowDdcCi=false (per-monitor)

**Location:** `~/.config/kwinoutputconfig.json`

**Applied when:** Always (universal stability fix)

**Why:** Disables DDC/CI control for each monitor. Prevents:
- NVIDIA I2C transfer errors
- Screen flickering
- Brightness control crashes

**How to set:** System Settings → Display → Click monitor → Uncheck "Control hardware brightness"

**Safe to remove?** No — causes flickering and errors.

**Rollback:**
```json
// Edit ~/.config/kwinoutputconfig.json
"allowDdcCi": true  // Change to true for specific monitor
```

---

### vrrPolicy=Never

**Location:** `~/.config/kwinoutputconfig.json`

**Applied when:** Multi-monitor setup

**Why:** Disables VRR/FreeSync. Prevents:
- Stuttering with mixed refresh rate monitors
- Inconsistent frame pacing
- Tearing on some configurations

**Safe to remove?** Yes — but may cause stuttering on multi-monitor.

**Rollback:**
```json
// Edit ~/.config/kwinoutputconfig.json
"vrrPolicy": "Always"  // or "Automatic"
```

---

## 4. Power Management

### CPU Governor: powersave

**Location:** `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`

**Applied when:** Always (universal with intel_pstate)

**Why:** With `intel_pstate` driver, "powersave" is dynamic (not fixed low frequency):
- Scales from min to max based on load
- Controlled by EPP (Energy Performance Preference)
- Integrates with asusctl/power-profiles-daemon

**Safe to change?** No — breaks power management integration.

**Note:** This is NOT the same as generic cpufreq "powersave".

---

### EPP: balance_performance

**Location:** `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference`

**Applied when:** Always (universal default)

**Why:** Balanced performance/power bias:
- `balance_power` — Good balance (default)
- `performance` — Maximum performance, higher power
- `power` — Maximum savings, lower performance

**Applied values by profile:**
| Profile | EPP Value |
|---------|-----------|
| Quiet | power |
| Balanced | balance_performance |
| Performance | performance |

**Safe to change?** Yes — but affects performance/power balance.

**Rollback:**
```bash
echo balance_performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference
```

---

### asusctl profile: Balanced

**Location:** ASUS laptop with asusctl

**Applied when:** `HAS_ASUSCTL=true` (ASUS laptop detected)

**Why:** Balanced profile provides:
- Fans at 0 RPM when idle/cool
- Ramps up when needed
- Good daily work profile

**Safe to change?** Yes — user preference.

**Rollback:**
```bash
asusctl profile -P Balanced
```

---

## 5. Memory & Swap

### vm.swappiness=133

**Location:** `/etc/sysctl.d/99-swappiness.conf` or runtime

**Applied when:** ZRAM configured

**Why:** Garuda-specific ZRAM optimization:
- Values >100 tell kernel to PREFER zram over keeping pages in RAM
- ZRAM is compressed RAM (faster than disk swap)
- Keeps more RAM free for file cache

**Safe to change?** Yes — but defeats ZRAM optimization.

**Rollback:**
```bash
sudo sysctl vm.swappiness=60
# Or permanent:
echo "vm.swappiness=60" | sudo tee /etc/sysctl.d/99-swappiness.conf
```

---

### vm.vfs_cache_pressure=100

**Location:** `/etc/sysctl.d/99-vm.conf`

**Applied when:** Always (universal)

**Why:** Controls how aggressively kernel reclaims inode/dentry cache:
- 100 = default behavior
- Lower = keep cache longer (better for file-heavy workloads)
- Higher = reclaim cache faster (more RAM for apps)

**Safe to change?** Yes — default is 100.

---

### vm.dirty_ratio=20

**Location:** `/etc/sysctl.d/99-vm.conf`

**Applied when:** Always (universal)

**Why:** Maximum percentage of RAM that can be filled with dirty (unwritten) data:
- 20% = reasonable default
- Prevents I/O stalls from too much dirty data

**Safe to change?** Yes — but may affect write performance.

---

### vm.dirty_background_ratio=10

**Location:** `/etc/sysctl.d/99-vm.conf`

**Applied when:** Always (universal)

**Why:** Percentage of RAM at which background writeback starts:
- 10% = start writing back early
- Prevents sudden I/O spikes

**Safe to change?** Yes — but may affect write bursts.

---

### ZRAM Configuration

**Location:** `/usr/lib/systemd/system/zram-generator.service` or `/etc/systemd/zram-generator.conf`

**Applied when:** Always (Garuda default)

**Why:** Compressed RAM block device used as swap:
- Faster than disk swap
- Algorithm: zstd (best compression ratio)
- Size: typically 50-100% of RAM

**Safe to disable?** Yes — but will use disk swap instead.

**Rollback:**
```bash
sudo systemctl disable --now zram-generator.service
sudo rm /etc/systemd/zram-generator.conf
```

---

## 6. I/O Scheduler

### kyber (NVMe)

**Location:** `/sys/block/nvme*/queue/scheduler`

**Applied when:** NVMe drive detected

**Why:** Optimized for NVMe SSDs:
- Low latency
- Good throughput
- Better than mq-deadline for desktop use

**Safe to change?** Yes — but may affect disk performance.

**Rollback:**
```bash
echo mq-deadline | sudo tee /sys/block/nvme0n1/queue/scheduler
# Or permanent via udev rule:
echo 'ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="mq-deadline"' | sudo tee /etc/udev/rules.d/60-scheduler.rules
```

---

## 7. System Services

### power-profiles-daemon

**Location:** systemd service

**Applied when:** Always (universal)

**Why:** Provides D-Bus interface for power profiles:
- Integrates with KDE Power Management
- Works with asusctl on ASUS laptops
- Controls CPU EPP and platform profiles

**Safe to disable?** No — breaks power management.

**Rollback:**
```bash
systemctl status power-profiles-daemon
```

---

### asusd

**Location:** systemd service

**Applied when:** `HAS_ASUSCTL=true` (ASUS laptop)

**Why:** ASUS laptop control daemon:
- Fan curves
- Power profiles
- Battery charging thresholds
- RGB lighting

**Safe to disable?** Yes — but loses ASUS-specific features.

**Rollback:**
```bash
sudo systemctl disable --now asusd
```

---

### ananicy-cpp

**Location:** systemd service

**Applied when:** Always (recommended)

**Why:** Automatic process priority manager:
- Lowers priority of background tasks
- Boosts interactive applications
- Improves system responsiveness

**Safe to disable?** Yes — but may feel less responsive.

**Rollback:**
```bash
sudo systemctl disable --now ananicy-cpp
```

---

### bluetooth

**Location:** systemd service

**Applied when:** `HAS_BLUETOOTH=true`

**Why:** Bluetooth support:
- Connect wireless devices
- Audio devices
- File transfer

**Safe to disable?** Yes — if not using Bluetooth.

**Rollback:**
```bash
sudo systemctl disable --now bluetooth
```

---

## 8. Security Settings

### Firewall

**Location:** firewalld or ufw

**Applied when:** User chooses to enable (currently inactive on test system)

**Why:** Network security:
- Blocks unsolicited incoming connections
- Allows outgoing by default
- Zone-based rules

**Recommendation:** Enable on all systems.

**Enable:**
```bash
# For firewalld:
sudo systemctl enable --now firewalld
sudo firewall-cmd --add-service=ssh --permanent  # If using SSH
sudo firewall-cmd --reload

# For ufw:
sudo ufw enable
sudo ufw allow ssh  # If using SSH
```

---

### SSH Hardening

**Location:** `/etc/ssh/sshd_config`

**Applied when:** SSH server installed

**Recommended settings:**
```
PermitRootLogin no
PasswordAuthentication no  # Use keys only
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
```

**Safe to apply?** Yes — but ensure you have SSH keys set up first.

---

## Summary: DO NOT TOUCH List

| Setting | Location | Risk if Changed |
|---------|----------|-----------------|
| `nvidia_drm.modeset=1` | GRUB | Breaks Wayland, sleep |
| `KWIN_DRM_NO_DIRECT_SCANOUT=1` | /etc/environment | Framebuffer errors |
| `allowDdcCi=false` | kwinoutputconfig.json | Screen flickering |
| `blurEnabled=false` | kwinrc | High CPU, lag |
| `vm.swappiness=133` | sysctl | ZRAM inefficiency |
| CPU governor | sysfs | Breaks asusctl integration |

---

## Summary: Safe to Customize

| Setting | Location | Effect |
|---------|----------|--------|
| EPP value | sysfs | Performance vs battery |
| asusctl profile | asusctl | Fan speed, power |
| KWin effects | kwinrc | Visual flair |
| I/O scheduler | sysfs | Disk behavior |
| Services | systemd | Features enabled |

---

## Rollback Commands Quick Reference

```bash
# Reset GRUB to defaults
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' /etc/default/grub
sudo update-grub

# Reset environment variables
sudo rm /etc/environment
echo -e "# Default Garuda environment\n" | sudo tee /etc/environment

# Reset KWin config
mv ~/.config/kwinrc ~/.config/kwinrc.backup
mv ~/.config/kwinoutputconfig.json ~/.config/kwinoutputconfig.json.backup
# Logout and login

# Reset swappiness
sudo sysctl vm.swappiness=60

# Disable ZRAM
sudo systemctl disable --now zram-generator.service
```
