# System Analysis: Thermal Instability & Performance Degradation

**Date:** 2026-06-13
**System:** ASUS TUF Gaming F15 (FX507ZR) — Garuda Linux KDE Plasma 6 (Wayland)
**Confidence Level:** 🟢 High — analysis based on frozen system state documentation, existing diagnostic scripts, and documented failure histories.

---

## Executive Summary

The system exhibits two classes of problems: **thermal instability** (GPU stuck at 40W idle, CPU temps reaching 96°C causing thermal shutdown) and **perceived lag/stutter** (KWin CPU at 50-80%, cursor lag, compositing stutter). These are NOT hardware defects — the i7-12700H + RTX 3070 + 32GB DDR5 should deliver a premium experience. The root causes are configuration misalignments in the compositor, GPU driver parameters, and power management stack, all of which have been previously documented but may have regressed.

**Impact by user symptom:**

| Symptom | Root Cause Category | Severity |
|---------|-------------------|----------|
| "Sometimes too hot" | GPU power state / thermal cascade | 🔴 Critical |
| "Sometimes laggy" | KWin compositor / CPU governor | 🔴 Critical |
| "Not sleek experience" | Cumulative config drift | ⚠️ Medium |

---

## C4 Level 1: System Context

```
┌──────────────────────────────────────────────────────────────────┐
│  User (single operator, ASUS TUF laptop)                        │
│  - KDE Plasma 6 desktop session (Wayland)                       │
│  - 3× 1440p displays (eDP-2 internal + DP-1 + HDMI-A-1)        │
└────────────┬─────────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
    ▼                 ▼
┌──────────┐   ┌──────────────┐
│ Garuda   │   │ Arch Linux    │
│ Linux OS │   │ AUR/Chaotic   │
│ (Kernel  │   │ Package Repos │
│  6.18-zen)│  └──────────────┘
└────┬─────┘
     │
     ├── NVIDIA RTX 3070 (proprietary nvidia-dkms)
     ├── Intel iGPU (i915 kernel module)
     ├── 32GB DDR5 RAM
     └── NVMe SSD (kyber scheduler)
```

## C4 Level 2: Container — Thermal & Performance Subsystems

```
┌─────────────────────────────────────────────────────────────────┐
│  Power Management Stack                                          │
│  ┌──────────┐  ┌──────────────────────┐  ┌──────────────────┐  │
│  │ asusctl  │→│ power-profiles-daemon │→│ intel_pstate      │  │
│  │ (fans,   │  │ (D-Bus profile API)  │  │ (CPU freq driver) │  │
│  │  profile)│  └──────────────────────┘  └────────┬─────────┘  │
│  └──────────┘                                     │             │
│                                                   ▼             │
│                                        ┌──────────────────────┐ │
│                                        │ EPP (balance_power)  │ │
│                                        │ /sys/.../energy_     │ │
│                                        │ performance_pref     │ │
│                                        └──────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│  GPU Power State Machine                                         │
│  ┌──────────┐     ┌──────────────┐    ┌─────────────────────┐  │
│  │ nvidia-  │────→│ P-State      │───→│ Power Draw          │  │
│  │ dkms     │     │ (P0→P8)      │    │ (idle: 5W target)   │  │
│  └──────────┘     └──────────────┘    └─────────────────────┘  │
│                                                                  │
│  CRITICAL PATHWAY: nvidia_drm.fbdev=1 → GPU can't enter D3     │
│  sleep → stuck at P2 (40W) → thermal cascade → 96°C shutdown   │
├─────────────────────────────────────────────────────────────────┤
│  Compositor Pipeline (KWin)                                      │
│  ┌──────────┐     ┌──────────────┐    ┌─────────────────────┐  │
│  │ Qt/QML   │────→│ KWin_wayland │───→│ DRM/KMS             │  │
│  │ Scene    │     │ Composites at │    │ (triple 1440p@165Hz)│  │
│  └──────────┘     │ 3×165Hz      │    └─────────────────────┘  │
│                   └──────────────┘                               │
│                                                                  │
│  Hot Paths: blur effects (50%+ CPU), shapecorners, wobblywindows│
│  Fixed Paths: coverswitch, fade, magiclamp (< 2% CPU each)      │
└─────────────────────────────────────────────────────────────────┘
```

---

## ADR-001: GPU Thermal Safety Policy

**Status:** Accepted (2025-12-30, reaffirmed 2026-03-07)
**Supersedes:** Original KWIN-HYBRID-GPU.md guidance (which recommended fbdev=1)

### Context

The system uses a hybrid Intel-NVIDIA GPU configuration. The NVIDIA driver historically required `nvidia_drm.fbdev=1` to resolve framebuffer errors (`GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT`). However, this parameter prevents the GPU from entering D3 sleep state, causing:

1. GPU stuck at 40W idle (target: 5W)
2. Video memory staying active during suspend
3. System overheating to 96°C → thermal shutdown/reboot
4. 8× higher energy waste at idle

### Decision

**`nvidia_drm.fbdev=1` shall NEVER be auto-applied.** It requires explicit user opt-in via `--force-fbdev` flag with a thermal safety warning. The framebuffer errors are harmless log noise — not actual display corruption.

### Options Considered

| Option | Thermal | Framebuffer | UX | Verdict |
|--------|---------|-------------|-----|---------|
| 1. `fbdev=1` always | 🔴 40W idle | ✅ No errors | ❌ 96°C | **Rejected** |
| 2. No `fbdev=1`, ignore errors | ✅ 5W idle | ⚠️ Log spam | ✅ Stable | **Selected** |
| 3. No `fbdev=1` + userspace KWin restart | ✅ 5W idle | ✅ Errors reduced | ✅ Stable | **Selected +**

### Consequences

- **Easier:** System stays cool, GPU idles properly
- **Harder:** Framebuffer errors appear in journal (harmless cosmetics)
- **Risk:** If user force-enables fbdev=1, thermal cascade returns

---

## ADR-002: KWin Compositor Effect Policy

**Status:** Accepted (2024-12-30)

### Context

With 3 monitors at 1440p 165Hz, KWin compositing is GPU-bound. Certain effects cause CPU-side rendering spikes:

| Effect | CPU Impact | Visual Benefit |
|--------|-----------|----------------|
| blurEnabled | 30-50% CPU | Aesthetic only |
| forceblurEnabled | 30-50% CPU | Third-party |
| shapecorners | 15-25% CPU | Minor rounding |
| wobblywindows | 10-20% CPU | Visual flair |
| coverswitch | <2% CPU | Alt+Tab UX |
| fade | <2% CPU | Window open/close |
| magiclamp | <2% CPU | Minimize animation |

### Decision

**Disable CPU-heavy effects (blur, forceblur, shapecorners, wobblywindows). Keep low-cost effects (fade, magiclamp, coverswitch).**

### Consequences

- **Easier:** KWin CPU drops from 50-80% to 15-25% at idle
- **Harder:** No transparency blur behind windows (cosmetic only)
- **Risk:** User may re-enable blur through System Settings UI, causing regression

---

## Root Cause Analysis: The "Sometimes Too Hot" Problem

### Causal Chain

```
nvidia_drm.fbdev=1 (IN GRUB)
       │
       ▼
GPU framebuffer kept active
       │
       ▼
GPU cannot enter D3 sleep state
       │
       ▼
Power draw floor raised: 5W → 40W (8× increase)
       │
       ▼
VRM/GPU area heats chassis → CPU thermal soak
       │
       ▼
CPU temps spike to 96°C
       │
       ▼
Thermal protection: emergency shutdown
```

### Detection Commands

```bash
# Check if fbdev=1 is active
grep "nvidia_drm.fbdev=1" /etc/default/grub

# Check current GPU power draw (should be ~5-15W at idle)
nvidia-smi --query-gpu=power.draw,pstate --format=csv

# Check CPU temps (should be 40-60C at idle)
sensors | grep -i "package\|tctl"
```

### Secondary Thermal Factors

1. **Power profile on Performance** — keeps GPU/CPU in max performance state, fans at 2500+ RPM constant
2. **KWin blur enabled** — 50%+ CPU = more heat
3. **`KWIN_DRM_NO_AMS=1`** — forces legacy KMS path, 40%+ extra CPU overhead
4. **Package cache bloat** — large /var/cache/pacman/pkg contributes to disk I/O heat

---

## Root Cause Analysis: The "Sometimes Laggy" Problem

### Causal Chain

```
Compositor CPU overhead
       │
       ▼
KWin rendering at 3× 1440p 165Hz
       │
       ├── blurEnabled=true → +30% CPU per frame
       ├── KWIN_DRM_NO_AMS=1 → legacy KMS, 40%+ CPU
       └── shapecorners → +15% CPU per window
       │
       ▼
Frame budget exceeded at 165Hz (6.06ms per frame)
       │
       ▼
Dropped frames → perceived stutter/lag
```

### Detection Commands

```bash
# Check KWin CPU
ps aux | grep kwin_wayland | grep -v grep | awk '{print $3"%"}'

# Check if blur is enabled
grep "blurEnabled\|forceblurEnabled" ~/.config/kwinrc

# Check if NO_AMS is set
grep "KWIN_DRM_NO_AMS" /etc/environment ~/.config/environment.d/*

# Check power profile (Quiet = throttled)
asusctl profile -p 2>/dev/null | grep "Active"
```

### Secondary Lag Factors

1. **Power profile on "Quiet"** — limits CPU frequency, causes UI stutter
2. **Swappiness=133 without ZRAM** — if ZRAM not active, aggressive swapping to disk
3. **DDC/CI enabled** — I2C bus contention causes display flicker and cursor lag
4. **Intel PSR (Panel Self Refresh) enabled** — known cause of stuttering on some panels
5. **GPU stuck in high P-state** — NVIDIA not entering P5/P8 idle, consuming power budget

---

## ISO 25010 Quality Attribute Evaluation

### 1. Functional Suitability — ⚠️ Medium
- ✅ System functions for all use cases
- ⚠️ KWin effects disabled sacrifice visual completeness for performance
- ⚠️ DDC/CI brightness control sacrificed for stability

### 2. Reliability — 🔴 High
- 🔴 `nvidia_drm.fbdev=1` causes thermal shutdown — **system becomes unreliable**
- ✅ Rollback scripts exist for all optimizations
- ⚠️ Sleep/wake stability depends on userspace hooks (no driver-level fix)

### 3. Performance Efficiency — ⚠️ Medium
- ✅ NVMe kyber scheduler, ZRAM with optimal swappiness, VM dirty ratios tuned
- 🔴 KWin compositor at 15-25% CPU for idle desktop is still high
- ⚠️ NVIDIA power management: P5 idle is acceptable, but P0/P2 at idle is broken

### 4. Usability — ⚠️ Medium
- ⚠️ User must understand power profiles (Quiet→lag, Performance→heat)
- ⚠️ GTK/Qt/Electron window button inconsistency requires manual fixes
- ✅ System health check script (`check`) provides guided diagnostics

### 5. Security — ✅ Low
- ✅ Firewall configuration available (not auto-enabled for safety)
- ✅ Failed SSH login monitoring in deep health check

### 6. Compatibility — ⚠️ Medium
- ⚠️ Hybrid GPU support requires specific kernel parameters
- ⚠️ Wayland + NVIDIA compatibility is improving but fragile
- ✅ Hardware detection script covers broad hardware profiles

### 7. Maintainability — ✅ Low
- ✅ Every setting documented with WHAT/WHY/ROLLBACK
- ✅ Rollback scripts for all optimization categories
- ✅ Hardware-agnostic architecture with conditional application

### 8. Portability — ⚠️ Medium
- ⚠️ ASUS-specific tools (asusctl, supergfxctl) create vendor lock-in
- ✅ Detection script gracefully degrades on non-ASUS hardware
- ⚠️ NVIDIA-specific GRUB parameters not portable to AMD/Intel-only systems

---

## Trade-off Analysis Matrix

| Trade-off | Optimize For | At Cost Of | Decision |
|-----------|-------------|------------|----------|
| GPU fbdev | Thermal safety (5W idle) | Harmless log errors | Accept errors |
| KWin effects | Low CPU (15-20%) | No transparency blur | Accept no blur |
| DDC/CI | Display stability | Brightness auto-control | Accept manual brightness |
| Power profile | Cooling + silence | No "turbo" at all times | Accept Balanced |
| KWin DRM | Multi-monitor stability | No direct scanout perf | Accept overhead |
| ZRAM swappiness | RAM compression efficiency | Slightly more CPU for compression | Accept 133 |

---

## Architecture Anti-Patterns Detected

### 1. 🔴 Leaky Abstraction — NVIDIA DRM fbdev
The `nvidia_drm.fbdev=1` parameter is a kernel-level toggle that leaks GPU power state management details into userspace configuration. The user must understand D3 sleep states and power draw thresholds to configure their display correctly.

### 2. ⚠️ Vendor Lock-in — ASUS-Specific Stack
The asusctl/supergfxctl/power-profiles-daemon stack is tightly coupled to ASUS hardware. While detection scripts gracefully degrade, the optimization scripts assume ASUS tooling.

### 3. ⚠️ Golden Hammer — GRUB Kernel Parameters
Every GPU issue was initially approached by adding GRUB parameters (`nvidia_drm.modeset=1`, `fbdev=1`, `amdgpu.sg_display=0`, `i915.enable_psr=0`). This pattern bloats the kernel command line and creates hard-to-debug interactions.

### 4. ✅ Resolved: Distributed Monolith for Config
The environment variable approach (`/etc/environment`, `~/.config/environment.d/*.conf`) was previously at risk of becoming a distributed monolith where env vars from different files interact unpredictably. The current `DO NOT ADD` list in SYSTEM-STATE.md mitigates this.

---

## Edge Case Stress Testing

### Load: 10×, 100×, 1000× Current Scale
- **10×**: Not applicable (single-user desktop, not a server)
- **100×**: If 100 similar laptops deployed, thermal issues ×100 would cause systemic overheating
- **Stress point**: Each laptop needs individual tuning due to ASUS firmware variance

### Failure: What Happens When Each Component Fails?

| Component | Failure Mode | Recovery |
|-----------|-------------|----------|
| KWin crash | SDDM restarts session | Auto-recovery via systemd |
| NVIDIA driver crash | DRM subsystem reset | Manual `modprobe -r nvidia && modprobe nvidia` |
| asusd crash | Fans default to BIOS curve | `systemctl restart asusd` |
| ZRAM failure | Kernel panic | Rare, no recovery |
| power-profiles-daemon crash | EPP not updated | `systemctl restart power-profiles-daemon` |
| `nvidia_drm.fbdev=1` thermal cascade | Emergency shutdown | Must remove GRUB parameter before reboot |

### Data: Edge Conditions
- **null**: All env var files absent → system boots with defaults (safe)
- **empty**: `kwinrc` empty → KWin uses factory defaults (blur ON → CPU spike)
- **max-length**: 10+ GRUB params → bootloader truncation risk (not observed)
- **invalid encoding**: Corrupted JSON in `kwinoutputconfig.json` → KWin falls back to auto-detect
- **concurrent writes**: Two tools writing to `/etc/environment` → last-write-wins, no locking

### Time: Clock Skew & Consistency
- **Clock skew**: NTP not critical for desktop, but journal timestamps differ if clock jumps
- **Timezone**: DISPLAY env var not set → Qt theme issues (unlikely)
- **Eventual consistency**: After applying optimizations, reboot is required for GRUB and udev changes
- **Window**: Maximum stale config window = time between optimization apply and reboot

### Security: Threat Model
- **Unauthorized config change**: Any process with user permissions can modify `~/.config/kwinrc` — blur can be silently re-enabled
- **Injection**: GRUB command line is parsed at boot — malicious kernel params can compromise system
- **Data exfiltration**: Not applicable (no network services exposed by these configs)
- **Replay attacks**: Not applicable

### Multi-Tenancy
- Not applicable — single-user desktop system
- If future multi-user: per-user `~/.config/kwinrc` is already isolated

---

## Diagnostic Priority Matrix

Run these checks in order to identify what's currently wrong:

### Priority 1: Critical (Immediate Thermal Risk)

| Check | Command | Expected | If Wrong |
|-------|---------|----------|----------|
| fbdev=1 in GRUB | `grep fbdev /etc/default/grub` | NOT present | Remove immediately + `update-grub` + reboot |
| GPU idle power | `nvidia-smi --query-gpu=power.draw,pstate --format=csv` | P5-P8, <20W | Check for GPU-using processes, fbdev=1 |
| CPU temp idle | `sensors \| grep Package` | <60°C | Check power profile, fans, dust |

### Priority 2: Performance (Lag/Stutter)

| Check | Command | Expected | If Wrong |
|-------|---------|----------|----------|
| KWin blur | `grep blurEnabled ~/.config/kwinrc` | `false` | Run `apply-optimizations.sh --category KWin` |
| KWin NO_AMS | `grep NO_AMS /etc/environment ~/.config/environment.d/*` | NOT present | Remove line and reboot |
| Power profile | `asusctl profile -p` | Balanced | `asusctl profile -P Balanced` |
| CPU governor | `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` | powersave | DO NOT CHANGE (intel_pstate dynamic) |
| EPP | `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference` | balance_power | Switch to Balanced profile |

### Priority 3: Stability (Flicker/Display)

| Check | Command | Expected | If Wrong |
|-------|---------|----------|----------|
| DDC/CI | `grep allowDdcCi ~/.config/kwinoutputconfig.json` | `false` on all | Disable in System Settings or run fix-ddc-config.sh |
| DRM_NO_DIRECT_SCANOUT | `grep KWIN_DRM_NO_DIRECT_SCANOUT /etc/environment` | `=1` | Run `apply-optimizations.sh --category KWin` |
| NO_DDCUTIL | `cat ~/.config/environment.d/kwin-fixes.conf` | `POWERDEVIL_NO_DDCUTIL=1` | Run `apply-optimizations.sh --category KWin` |

### Priority 4: Background (Optimization)

| Check | Command | Expected | If Wrong |
|-------|---------|----------|----------|
| Services | `systemctl is-active asusd power-profiles-daemon ananicy-cpp` | all active | `systemctl enable --now <svc>` |
| Swappiness | `cat /proc/sys/vm/swappiness` | 133 | Check /etc/sysctl.d/99-swappiness.conf |
| I/O scheduler | `cat /sys/block/nvme0n1/queue/scheduler` | `[kyber]` | udev rule may need refresh |
| Package cache | `du -sh /var/cache/pacman/pkg/` | <5GB | `sudo paccache -rk2` |

---

## Verification Checklist

After applying fixes:

- [ ] GPU idle power: <20W at desktop idle (target: 5-15W)
- [ ] CPU idle temp: 40-60°C
- [ ] KWin CPU: 15-25% with 3 monitors at 165Hz
- [ ] GPU P-state: P5 or P8 at idle
- [ ] No `nvidia_drm.fbdev=1` in GRUB
- [ ] `blurEnabled=false` AND `forceblurEnabled=false` in kwinrc
- [ ] No `KWIN_DRM_NO_AMS=1` anywhere in environment files
- [ ] `POWERDEVIL_NO_DDCUTIL=1` in kwin-fixes.conf
- [ ] `power-profiles-daemon` and `asusd` active
- [ ] Power profile = Balanced
- [ ] EPP = balance_power
- [ ] Journal has no critical (level 0-2) messages from this boot
- [ ] No GPU-related hardware errors in dmesg
- [ ] Sleep/wake cycle completes without freeze (test 2-3 times)

---

## Migration Path

### Immediate (Inspect Only — No Changes)

```bash
# Run the deep health check to see current state
check --deep

# Detect hardware and review
./scripts/tools/detect-hardware.sh --summary

# Check for the most dangerous setting
grep "nvidia_drm.fbdev=1" /etc/default/grub && echo "⚠ DANGER: fbdev=1 found! Remove immediately." || echo "✓ Safe"
```

### Phase 1: Fix Critical Thermal Issues

```bash
# 1. Verify and remove fbdev=1 if present
sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub
sudo update-grub

# 2. Set power profile to Balanced
asusctl profile -P Balanced

# 3. Reboot
sudo reboot
```

### Phase 2: Fix Performance Issues

```bash
# Apply KWin optimizations (disables blur, sets DRM_NO_DIRECT_SCANOUT, DDC fix)
sudo ./scripts/tools/apply-optimizations.sh --category KWin

# Verify blur is disabled
grep "blurEnabled" ~/.config/kwinrc
# Must show: blurEnabled=false

# Log out and log in
```

### Phase 3: Verify & Monitor

```bash
# Quick health check
check

# Monitor GPU state at idle (should be P5/P8, <20W)
watch -n2 'nvidia-smi --query-gpu=power.draw,pstate --format=csv'

# Monitor CPU temps
watch -n2 'sensors | grep -E "Package|Core 0"'
```

### Rollback Strategy

Every optimization script has a corresponding rollback:
```bash
# Individual category rollback
sudo ./scripts/tools/rollback-optimizations.sh --category GPU
sudo ./scripts/tools/rollback-optimizations.sh --category KWin
sudo ./scripts/tools/rollback-optimizations.sh --category power

# Full rollback
sudo ./scripts/tools/rollback-optimizations.sh
```

**Rollback decision threshold:** If CPU temps exceed 85°C at idle or GPU power exceeds 30W at idle after any change → rollback immediately.

---

## What Success Looks Like

| Metric | Current (Likely) | Target |
|--------|-----------------|--------|
| GPU idle power | 40W (if fbdev=1) or 20W | **5-15W** |
| CPU idle temp | 70-96°C | **40-60°C** |
| KWin CPU | 50-80% | **15-25%** |
| Desktop feel | Stutter/lag | **Butter-smooth at 165Hz** |
| Blur effects | Enabled (CPU hog) | **Disabled, no visible difference** |
| Sleep/wake | Broken/crash | **Works within 3 seconds** |
| Fan noise | Constant 2500+ RPM | **0 RPM idle, ramp only under load** |

---

## References

- `docs/SYSTEM-STATE.md` — Frozen configuration state (authoritative)
- `docs/SLEEP-WAKE-ISSUES.md` — Sleep/wake fix hierarchy
- `docs/KWIN-HYBRID-GPU.md` — Deprecated fbdev guidance (kept for history)
- `docs/HARDWARE-AGNOSTIC-ARCHITECTURE.md` — Conditional optimization design
- `docs/QUICK-REFERENCE.md` — Daily commands and optimal baselines
- `scripts/tools/system-health-check.sh` — `check` command implementation
- `scripts/tools/detect-hardware.sh` — Hardware profile detection
- `scripts/tools/apply-optimizations.sh` — Conditional optimization application
- `scripts/tools/rollback-optimizations.sh` — Optimization rollback
