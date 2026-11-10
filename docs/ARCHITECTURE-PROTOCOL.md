# Workstation Architecture & Maintenance Protocol

**Status:** adopted 2026-11-10, corrected against live measurements on the FX507ZR.
**Purpose:** a workstation that keeps an interactive session alive while autonomous AI workloads run, update, and fail — without taking the host down.

> The draft this replaces prescribed two mechanisms that are **not possible on this machine**: `OOMScoreAdjust=-500` on terminals and `MemoryHigh` below `MemoryMax`. Both were tested and are documented below with the mechanism that actually works.

---

## 1. Philosophy

1. **The interactive session is Tier-0.** The compositor, display driver, window manager and terminal must survive any workload failure.
2. **Agents, test runners and compilers are ephemeral.** A leak, a fork storm or a lock-up must cost one scope, never the session.
3. **Predictability beats bleeding edge.** A broken boot or a dead Wayland session is a critical failure; hardware enablement is tempered by a stable kernel baseline.

---

## 2. Corrected mechanisms (measured 2026-11-10)

| Draft claim | Verdict | What actually enforces it here |
|---|---|---|
| `OOMScoreAdjust=-500` on terminals / `oom_score_adj=-500` | **Impossible unprivileged** | An unprivileged write of a negative value to `/proc/self/oom_score_adj` fails with `Permission denied`; systemd 262.1 rejects the property on a transient scope (`Unknown assignment: OOMScoreAdjust=-500`); systemd-oomd ignores `oom_score_adj` entirely. Replacement: **raise the harness's own score to 900 inside its scope** and mark the terminal/compositor `ManagedOOMPreference=omit`. |
| `MemoryHigh` as a soft limit | **Rejected** | Measured on this host: `MemoryHigh` below `MemoryMax` stalls an anonymous-heavy process in reclaim without ever firing the kill — a livelock. Use a hard `MemoryMax` only. |
| `OOMPolicy=kill` on the scope | Accepted, not the protection | The cgroup's own `MemoryMax` is what terminates the scope; `OOMPolicy` only affects multi-process units. |
| External displays through the dGPU, light desktop on the iGPU | **Not possible here** | Both external ports are wired to the dGPU: `card1` (NVIDIA) owns `DP-1` (**the USB-C port**) and `HDMI-A-1`; `card2` (Intel) owns only `eDP-2`. KWin composites the externals on the dGPU, 33–52 W at the desktop. The only lever is refresh (144→60 Hz: 26 W, P3→P5) or cooling maintenance. |
| LTS kernel baseline | **Installed** | `linux-lts 6.18.58-1` with DKMS `nvidia/615.78.08, 6.18.58-1-lts` and `/boot/initramfs-linux-lts.img`; not the default kernel; boot test pending. Installer: `scripts/tools/lts-fallback-install.sh`. |
| Block unannounced NVIDIA bumps | Not via `IgnorePkg` | `nvidia-open-dkms` pins an exact `nvidia-utils=…` version; pinning half the pair aborts `garuda-update`. The snapshot-before-update + `snapper rollback` path is the control. |
| ZRAM + NVMe swapfile | **True** | 32 GiB `/swap/swapfile` (prio -1) + 31 GiB zram (prio 100); zram is used first. |
| Wayland explicit sync | **True** | NVIDIA 615 ≥ 555, KWin 6.8.1; nothing to enable. |
| Battery charge threshold | **Applied** | 80 % via `asusctl battery limit 80` (asusd), unit `systemd/battery-charge-limit.service`. |

---

## 3. The two layers

### Layer 1 — hardware-agnostic runtime

| Concern | Mechanism | File |
|---|---|---|
| Scope containment | `systemd-run --user --scope --slice=harness.slice` with `MemoryMax`/`MemorySwapMax` per scope | `scripts/tools/harness-run.sh` |
| Slice ceiling | 18 GiB / 4 GiB, `ManagedOOMMemoryPressure=auto` | `~/.config/systemd/user/harness.slice{,.d/zz-oom.conf}` |
| Per-scope fairness | 9 GiB / 2 GiB per instance (one mature instance cannot starve another) | `scripts/tools/harness-run.sh` |
| Graceful degradation | watchdog on `memory.stat` anon → SIGTERM at 85 % → `nocowboy --continue` respawn | `scripts/tools/harness-run.sh` |
| Terminal/compositor immunity | `ManagedOOMPreference=omit` re-applied every 10 s to WezTerm instances and `plasma-{kwin_wayland,plasmashell,kded6}` | `scripts/tools/oom-guard.sh` |
| CPU burst containment | `CPUQuota=400%`, `CPUWeight=50` on `harness.slice` | `scripts/tools/thermal-guard.sh` |
| Non-crashing memory strategy | L0 app retention, L1 per-scope, L2 supervisor, L3 backpressure | `docs/ADR-harness-memory.md` |
| Update pipeline | mirrors → DB refresh → snapshot → download → TTY install → reboot | `scripts/tools/update-engine.sh`, `update-now.sh` |
| Snapshot enforcement | snap-pac pre/post + `grub-btrfs-snapper.path` (enabled) | system packages |

### Layer 2 — hardware adaptation (FX507ZR)

| Concern | Mechanism | File |
|---|---|---|
| Thermal | display topology (both externals on the dGPU), 60 Hz option, PL1 cap `ppt_pl1_spl` (watts), fan/EC defaults | `docs/system-thermal-lag-analysis.md`, `scripts/tools/thermal-guard.sh` |
| Power profile | `Performance` on AC, `Quiet` on battery; `Balanced` is unsafe on this EC (fan blow-up) | `docs/SYSTEM-STATE.md` |
| Battery | 80 % cap via `asusctl` | `systemd/battery-charge-limit.service` |
| Display | per-output scale/refresh; `kscreen-doctor` mode indices | `docs/QUICK-REFERENCE.md` |
| Sleep | sleep/suspend/hibernate targets masked (14 fixes failed; decision documented) | `docs/SLEEP-WAKE-ISSUES.md` |
| Kernel fallback | LTS installed, DKMS built, boot entry present | `scripts/tools/lts-fallback-install.sh` |

---

## 4. Maintenance pipeline

The protocol's staged model is implemented as a **prepared, not applied** update:

1. `sudo ./scripts/tools/update-engine.sh prepare` — refresh mirrors, `pacman -Syy`, fix local deps, take a snapshot, download every package. Safe under Plasma; touches no live binary.
2. `sudo ./scripts/tools/update-now.sh` — queues a transient system unit, stops the GUI, installs on tty1, reboots. This is the only step that changes the system.
3. Rollback if the reboot fails: GRUB → `Garuda Linux snapshots` → boot the pre-update snapshot → `sudo snapper -c root rollback <N>` → reboot.

**No automatic apply.** A timer may *prepare* off-peak; installing always requires an explicit TTY run.

### Guardrail: why there is no `pacman` interceptor

The draft's wrapper cannot work as designed: `sudo` resolves `pacman`/`garuda-update` through `secure_path`, so a user-PATH wrapper is never consulted, and a system-wide interceptor is fragile against every script that calls pacman (including the other agents on this machine). The guardrail is instead structural:

- `update-engine.sh install` refuses to run while a graphical session is active;
- `update-now.sh` stops the compositor before touching Qt/Plasma/Mesa — the 2026-10-23 freeze is what that prevents;
- the snapshot is mandatory before the transaction.

---

## 5. Enforcement contract

| Objective | Policy | Enforced by | Status |
|---|---|---|---|
| Terminal availability | never killed by memory starvation | `omit` on terminal/compositor units + harness score 900 inside its scope | **live** |
| Workload isolation | runaway memory/CPU cannot freeze the desktop | `harness.slice` 18 GiB / 4 GiB, per-scope 9 GiB / 2 GiB, CPU 400 %, weight 50 | **live** |
| Graceful failure | an overflow restarts the session, not the TUI | anon watchdog → SIGTERM → `--continue` | **live** (L0 app fix in progress) |
| Hardware stability | a bad update cannot brick the machine | LTS fallback + snapshot + rollback | **installed, boot test pending** |
| Thermal ceiling | no sustained 98 °C bursts | CPU quota, PL1 45 W, 60 Hz option | **quota + PL1 live** |
| Update discipline | no unvetted mid-day upgrades | prepare/install split + TTY + snapshot | **live, manual** |
| Advisory awareness | manual interventions surface before updating | `informant` | **not installed** (root) |
| Off-peak preparation | updates staged automatically | systemd timer around `prepare` | **not installed** (root) |

---

## 6. Open items (root or physical)

```bash
# advisory guard
sudo pacman -S informant

# LTS boot test (the point of the install)
# reboot -> GRUB -> Advanced options for Garuda Linux -> linux-lts -> uname -r

# staged upgrade, when convenient
sudo ./scripts/tools/update-engine.sh prepare
sudo ./scripts/tools/update-now.sh        # stops the GUI, reboots

# physical: dust out the fin stack, repaste (PTM7950-class)
```
