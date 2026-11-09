# WezTerm OOM containment — incident, decision, runbook

Status: accepted (design authority: architect). Implemented by
`scripts/tools/oom-guard.sh`, `scripts/tools/harness-run.sh`,
`scripts/tools/oom-forensics.sh`.

## Why WezTerm died

On 2026-11-09 at 21:00:06 the whole WezTerm unit was killed while an AI
development harness was running inside it.

```
systemd-oomd[869]: Marked /user.slice/user-1000.slice/user@1000.service/app.slice/
  app-org.wezfurlong.wezterm@5a71795af6ba45f2bfe9ca4545189c59.service for killing
  due to memory pressure for /user.slice/user-1000.slice/user@1000.service/app.slice
  being 94.49% > 80.00% for > 20s with reclaim activity
systemd[1313]: app-org.wezfurlong.wezterm@5a71795af6ba45f2bfe9ca4545189c59.service:
  systemd-oomd killed some process(es) in this unit.
```

The victim cgroup held 14.7 G at that moment.

Three facts explain the outcome:

1. **The killer was systemd-oomd, not the kernel OOM killer.**
   `journalctl -b -k | grep -iE 'oom-kill|killed process'` is empty for that
   boot. oomd acts on cgroup pressure (PSI) before the kernel ever reaches OOM.
2. **The policy comes from systemd itself:**
   `/usr/lib/systemd/user/slice.d/10-oomd-per-slice-defaults.conf` sets
   `ManagedOOMMemoryPressure=kill` and `ManagedOOMMemoryPressureLimit=80%` on
   *every* user slice. `oomctl` confirms `user@1000.service`, `app.slice` and
   `session.slice` are monitored at 80 % for 20 s. A kill-enabled cgroup is not
   itself a candidate — oomd picks a **leaf descendant** of it.
3. **The terminal and the harness shared one leaf cgroup.** WezTerm is started
   by the KDE portal as a *transient* unit
   `app-org.wezfurlong.wezterm@<uuid>.service` in `app.slice`
   (`FragmentPath=/run/user/1000/systemd/transient/…`, empty `DropInPaths`,
   `OOMScoreAdjust=200`). Every shell and every harness process launched in it
   lives in that same cgroup (verified through `/proc/<pid>/cgroup`), so the
   fattest leaf under `app.slice` *was* the terminal.

Resources were not short: 30.9 G RAM, 62.9 G swap (31 G zram zstd at priority
100, 32 G btrfs swapfile at priority -1), 5.7 G swap in use.

## Why the advice found online is wrong

The common "protect your terminal from OOM" recipe does not address this
failure mode:

1. **`OOMScoreAdjust=-500` on the terminal is ignored by oomd.**
   oomd selects a cgroup by PSI and sends SIGKILL to the whole cgroup; it never
   reads `oom_score_adj`. The 21:00 kill happened while every process in that
   unit already had `oom_score_adj=200`. It only matters for the kernel OOM
   killer, which did not fire.
2. **`MemoryMax=24G` on a 30.9 G machine is not a cap.**
   It leaves ~7 G for Plasma, kwin, WezTerm, browsers and the harness's own
   overhead — the same pressure that triggered the kill. Sizing must be derived
   from RAM and the observed peak, not copied.
3. **Swap was never short.** 5.7 G of 62.9 G was in use. The real (minor)
   finding is `zram-size=ram` with `backing_dev=none`: compressed pages can
   never be written back, so once zram fills the btrfs swapfile absorbs
   everything. That is a follow-up, not the cause.
4. **`systemctl --user edit` on `user@1000` targets the wrong layer.**
   The `kill` flag lives on the slices, shipped in `/usr/lib`, and raising the
   limit to 90 % makes kills *later and harsher* (thrash first, kill anyway).
   The correct knob is `ManagedOOMPreference` on the cgroup that must not die.
5. **A desktop-environment switch is irrelevant.** A lighter DE frees a few
   hundred MB at idle; the pressure comes from the harness.

## Decision

Three layers. All user-level: no root, no system units, no swap/zram/sysctl
changes, systemd-oomd stays enabled.

### L1 — containment (the actual fix)

`~/.config/systemd/user/harness.slice`:

```ini
[Slice]
MemoryMax=18G
MemorySwapMax=4G
ManagedOOMMemoryPressure=auto
```

The vendor ships `/usr/lib/systemd/user/slice.d/10-oomd-per-slice-defaults.conf`,
and drop-ins override the main unit file — even a main file in `~/.config`. The
same block is therefore shipped as
`~/.config/systemd/user/harness.slice.d/zz-oom.conf`; without it the effective
value stays `kill` at 80 % (measured).

| Value | Derivation |
| --- | --- |
| `MemoryMax=18G` | hard cap: 58 % of 30.9 G RAM, +22 % above the observed 14.7 G peak; leaves ≥11 G for the desktop |
| no `MemoryHigh` | a 16 G soft limit was measured to **livelock** the failure mode it was meant to soften: with `MemoryHigh=16G` the allocator plateaus at 16.4-16.6 G, swap pinned at the 4 G cap, and the 18 G `MemoryMax` is reached only after ~8 minutes (measured over 100 s: +0.16 G, no OOM). Without the soft limit the cap is reached in ~12 s and the kill is clean. One hard cap, one kill path, deterministic. |
| `MemorySwapMax=4G` | zram-backed grace for spikes; caps the harness at 22 G total; prevents btrfs swapfile thrash |
| `ManagedOOMMemoryPressure=auto` | deliberate opt-out of the vendor `kill@80%`: the deterministic hard cap is the only kill mechanism for the harness, oomd must not race it |

Launcher `harness` (`scripts/tools/harness-run.sh`):

```bash
exec systemd-run --user --scope --collect \
    --slice=harness.slice \
    -p MemoryAccounting=yes \
    -- /bin/bash -c 'echo 900 > /proc/self/oom_score_adj 2>/dev/null
    exec "$@"' harness "$@"
```

`OOMScoreAdjust=900` cannot be passed to `systemd-run -p` on a scope
(`Unknown assignment: OOMScoreAdjust=900`, verified on systemd 262), and
`set-property` cannot change it at runtime either. The launcher therefore raises
`/proc/self/oom_score_adj` from inside the scope immediately before `exec`;
raising is always permitted unprivileged and every child inherits it (verified:
`900` inside the scope, and the containment kill records `oom_score_adj:900`).

When the harness exceeds 22 G total, the kernel cgroup OOM kills a process
**inside the scope**. WezTerm is not in that cgroup and survives.

### L2 — immunity for what must not die

- **WezTerm** — its unit is transient and has no drop-ins, so protection is
  applied at runtime: `oom-guard.timer` (10 s) runs
  `systemctl --user set-property <unit> ManagedOOMPreference=omit` for every
  `app-org.wezfurlong.wezterm@*` unit. Verified to work rootless on transient
  units.
- **Plasma** — `plasma-kwin_wayland.service`, `plasma-plasmashell.service`,
  `plasma-kded6.service` get persistent drop-ins
  (`~/.config/systemd/user/<unit>.d/zz-oom.conf`) **and** the runtime
  `set-property` so the running units are protected immediately. Killing kwin
  or plasmashell loses the whole session, which is worse than the original
  problem.

### L3 — policy (unchanged)

`app.slice` and `session.slice` keep the vendor `kill@80%`/20 s. Browsers stay
the fallback victims. systemd-oomd is not disabled and its config is untouched.

### Rejected alternatives

| Option | Why rejected |
| --- | --- |
| Custom `~/.local/share/applications/org.wezfurlong.wezterm.desktop` with `OOMScoreAdjust=-900` and `Slice=terminal.slice` | `OOMScoreAdjust` is inherited by every child. A harness launched raw inside the terminal would inherit `-900`, so a kernel-OOM event would target kwin/plasmashell (session loss) instead of the terminal. Also, KDE's klauncher may still wrap the Exec in its own `app-…@uuid` transient unit, so the override may not even escape the portal wrapper. |
| Disable systemd-oomd / edit `user@1000` | Wrong layer: the kill flag is on the slices and per-slice prevents nothing. Disabling oomd trades a killed terminal for a thrashed machine and a kernel OOM that can take the compositor. |
| Expand swap / fix zram `backing_dev` | Swap was never short (5.7/62.9 G). A zram change is root-level boot configuration and not the cause of this crash. |
| Runtime guard on a 10 s timer instead of a persistent unit | 10 s is far below oomd's 20 s pressure duration, and a freshly launched terminal cgroup starts tiny. Accepted residual risk (below). |

## Runbook

Install (idempotent, rootless — note: `~/local/bin` must be in `$PATH`, which
it is on this machine):

```bash
./scripts/tools/oom-guard.sh --dry-run     # see exactly what changes
./scripts/tools/oom-guard.sh               # install
./scripts/tools/oom-guard.sh --install     # same, explicit
./scripts/tools/oom-guard.sh --uninstall   # full rollback
```

Launch heavy work through the launcher:

```bash
harness nocowboy              # or any command: harness <cmd...>
harness -- bun run build
```

Verify the guard is live:

```bash
systemctl --user is-active oom-guard.timer
systemctl --user show harness.slice -p MemoryHigh -p MemoryMax -p MemorySwapMax -p ManagedOOMMemoryPressure
systemctl --user show "$(systemctl --user list-units --type=service --no-legend --plain 'app-org.wezfurlong.wezterm@*' | awk 'NF{print $1}')" -p ManagedOOMPreference
oomctl
```

After the next "why did something die" event:

```bash
./scripts/tools/oom-forensics.sh
```

It prints `oomctl`, the last oomd kill decisions and kernel OOM lines for this
boot, memory pressure, per-unit memory, and the top RSS consumers. It writes
nothing.

## Residual risks

- **10 s guard window.** A terminal launched and blown up within one timer tick
  is unprotected. Negligible: oomd needs ≥20 s of sustained pressure, and a
  fresh terminal cgroup is small.
- **Harness launched raw (without `harness`).** It lands back in the terminal's
  cgroup, which is `ManagedOOMPreference=omit`; oomd will then sacrifice a
  browser cgroup instead of the terminal. The terminal survives — the browser
  tab set does not. Always launch heavy work through `harness`.
- **zram without a backing device.** Under extreme pressure compressed pages
  cannot be written back and the btrfs swapfile absorbs everything, which is
  slow. Follow-up, out of scope for this fix.
- **Kernel-OOM ordering.** Without the launcher the harness inherits
  `oom_score_adj=200` from the portal unit; with it, `900`. Either way it is a
  likelier kernel-OOM victim than Plasma, which is the desired ordering.
