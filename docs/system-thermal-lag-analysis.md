# System Analysis: Thermal Instability & Performance Degradation

**Date:** 2026-06-13 (corrected 2026-11-10 against live measurements)
**System:** ASUS TUF Gaming F15 (FX507ZR) — Garuda Linux KDE Plasma 6 (Wayland)
**Confidence Level:** 🟢 High for the live measurement below; the 2026-06-13 analysis is kept for history and superseded where they disagree.

> **Corrections of 2026-11-10 (measured, not inferred).**
> 1. `nvidia_drm.fbdev=1` is **not a GRUB flag on this system** — the cmdline has no such parameter, and `fbdev`/`modeset` are `Y` because nvidia-open 615 defaults them. Deleting a GRUB argument changes nothing. The 2026-06-13 causal chain below is therefore historical.
> 2. The real idle-power driver is the **display topology**: `card1` (NVIDIA) owns `DP-1` and `HDMI-A-1` — `DP-1` is the USB-C DP port on this unit, so **both external ports are wired to the dGPU**. `card2` (Intel) owns only `eDP-2`; its `DP-2`/`DP-3` are disconnected and are not physical ports. KWin composites both externals on the dGPU, so it never reaches D3. Measured: `P0/P3`, **35–52 W**, 13–34 % util, 62–63 °C, CPU package 82–88 °C, EC fans **4000–6300 rpm**.
> 3. The fan speed follows GPU/CPU power, **not the profile label** — the same `Performance` profile measured 4000/4200 rpm, 6000/6300 rpm and 4400/4700 rpm at different moments. With the AI harness running (CPU package 86–92 °C) the fans track CPU heat, not the 33 W GPU.
> 4. `asusctl profile set Balanced` is **not** the quiet profile on this EC: it drove the fans to near-maximum RPM (a thermal scare, hours of recovery). Keep `Performance` on AC and `Quiet` on battery.

### Applied guards (2026-11-10)

`harness.slice` carries a CPU quota (unprivileged, persistent, survives reboot):

```ini
# ~/.config/systemd/user/harness.slice.d/zz-cpu.conf
[Slice]
CPUQuota=400%
CPUWeight=50
```

Measured: two harness instances plus parallel `bun test` workers took ~5.4 of 20 threads. The quota caps the whole slice at 4 threads and `CPUWeight=50` lets the desktop preempt. In a 60 s burst the package fell **97 °C → 71 °C** while the test workers paused and climbed back to 97 °C when they resumed — that is, the quota limits parallelism but the hotspot is single-core boost, not thread count.

The hotspot lever needs root and is scripted:

```bash
./scripts/tools/thermal-guard.sh status            # read-only: temp, fans, PL1/PL2, EPP, throttle counters, quota
sudo ./scripts/tools/thermal-guard.sh cap --pl1 45 # sustained PL1 45 W, PL2 untouched, boot unit installed
sudo ./scripts/tools/thermal-guard.sh revert       # remove the boot unit (PL1 returns to firmware default at reboot)
```

Gate before keeping the cap: throttle ms/min must drop **and** a timed build must not regress more than ~10 %.

---

## Executive Summary

**2026-06-13 assessment — superseded by the corrections above.** The system exhibits two classes of problems: **thermal instability** (GPU stuck at 40W idle, CPU temps reaching 96°C causing thermal shutdown) and **perceived lag/stutter** (KWin CPU at 50-80%, cursor lag, compositing stutter). These are NOT hardware defects — the i7-12700H + RTX 3070 + 32GB DDR5 should deliver a premium experience. The root causes are configuration misalignments in the compositor, GPU driver parameters, and power management stack, all of which have been previously documented but may have regressed.

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

**Update 2026-11-10:** the decision is moot in form — on nvidia-open 615 both `modeset` and `fbdev` default to `Y` and no GRUB flag exists. The 40 W floor measured here is caused by `DP-1` + `HDMI-A-1` being wired to the dGPU, not by this module parameter. Do not spend time on the GRUB argument; spend it on the connector.

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

**Measured chain (2026-11-10):**

```
Two external displays (DP-1 + HDMI-A-1) wired to the dGPU (card1, NVIDIA)
       │
       ▼
KWin composites them on the dGPU; it never reaches D3
       │
       ▼
Idle power floor: 35–52 W at P0/P3, 13–34 % util
       │
       ▼
GPU 62–63 °C + CPU package 82–88 °C at the desktop
       │
       ▼
EC ramps fans to 4000–6300 rpm (follows load, not the profile label)
```

**Historical chain (2026-06-13, superseded):** it blamed `nvidia_drm.fbdev=1` set in GRUB for the 40 W floor. That premise no longer holds: the parameter is absent from the cmdline, the driver defaults it to `Y`, and the measured floor is explained by the display topology above.

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

# Check power profile (Performance on AC; Quiet throttles and feels slow)
asusctl profile get 2>/dev/null | grep "Active"
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
| `nvidia_drm` params | `cat /sys/module/nvidia_drm/parameters/{modeset,fbdev}` | `Y` / `Y` (driver default) | Not a GRUB flag; do not chase it. See the display-topology row |
| Displays on the dGPU | `for c in /sys/class/drm/card*-*/status; do …; done` | NVIDIA owns only what it must | External monitors on `card1` keep the dGPU awake — this is the real idle-power floor |
| GPU idle power | `nvidia-smi --query-gpu=power.draw,pstate --format=csv` | P5-P8, <20W | Check for GPU-using processes, fbdev=1 |
| CPU temp idle | `sensors \| grep Package` | <60°C | Check power profile, fans, dust |

### Priority 2: Performance (Lag/Stutter)

| Check | Command | Expected | If Wrong |
|-------|---------|----------|----------|
| KWin blur | `grep blurEnabled ~/.config/kwinrc` | `false` | Run `apply-optimizations.sh --category KWin` |
| KWin NO_AMS | `grep NO_AMS /etc/environment ~/.config/environment.d/*` | NOT present | Remove line and reboot |
| Power profile | `asusctl profile get` | `Performance` (AC) / `Quiet` (battery) | Do **not** set `Balanced` — measured fan blow-up. See the correction block |
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
# 1. Confirm the DRM parameters are driver defaults, not stale GRUB flags
cat /sys/module/nvidia_drm/parameters/modeset /sys/module/nvidia_drm/parameters/fbdev
grep -n nvidia_drm /etc/default/grub || echo "no nvidia_drm flags in GRUB (correct)"

# 2. Read the display topology: which GPU owns which output
for s in /sys/class/drm/card*-*/status; do
    printf '%s = %s\n' "$(dirname "$s" | xargs basename)" "$(cat "$s")"
done

# 3. Measure before any change
nvidia-smi --query-gpu=power.draw,utilization.gpu,pstate,temperature.gpu --format=csv,noheader
grep -H . /sys/class/hwmon/hwmon*/fan*_input
```

**There is no "move the monitor to the iGPU" step on this unit.** Both external ports are wired to the dGPU: the USB-C monitor enumerates as `card1-DP-1`, next to `card1-HDMI-A-1`; the iGPU's `DP-2`/`DP-3` are disconnected and not exposed as physical ports.

**The one measurable lever is refresh rate.** Measured 2026-11-10, both externals 2560x1440:

| Externals | dGPU power | P-state | fans |
|---|---|---|---|
| 144 Hz + 144 Hz | **33.6 W** | P3 | 4400 / 4700 rpm |
| 60 Hz + 60 Hz | **26.0 W** | P5 | 4500 / 4700 rpm |

~7.5 W (~22 %) and one P-state, instantly reversible; the fans did not drop because the CPU package was at 86–92 °C under the AI harness — at that moment the fans were following CPU heat. Use 60 Hz on the externals if you want the power back; accept the fan noise under CPU-heavy work. Keep `Performance` on AC — never `Balanced`.

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
| GPU idle power | **33–52W** at 144 Hz on both externals | **~26W** measured at 60 Hz; the iGPU route is not available on this unit |
| CPU idle temp | 70-96°C | **40-60°C** |
| KWin CPU | 50-80% | **15-25%** |
| Desktop feel | Stutter/lag | **Butter-smooth at 165Hz** |
| Blur effects | Enabled (CPU hog) | **Disabled, no visible difference** |
| Sleep/wake | Broken/crash | **Works within 3 seconds** |
| Fan noise | **4000–6300 RPM**; follows the CPU package under AI load | Not a defect here: both externals are on the dGPU and the CPU runs 86–92 °C under the harness |

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
