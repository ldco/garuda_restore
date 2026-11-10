# ADR — Non-crashing memory strategy for the NoCowboy harness

**Status:** Proposed (architect) · **Date:** 2026-11-10 · **Supersedes the "deterministic hard cap" philosophy of `docs/OOM-WEZTERM.md` (keeps its containment, adds non-fatal degradation).**

## Context

`docs/OOM-WEZTERM.md` fixed the *wrong victim*: the terminal survives, only the misbehaving harness scope dies. The requirement now escalates the guarantee: the harness itself must not be SIGKILLed. Measured live (2026-11-10 10:03 MSK), the kill is the kernel cgroup OOM (`constraint=CONSTRAINT_MEMCG`), not oomd, and it fires when one long-lived instance's JS heap reaches the shared 18 GiB slice cap.

## Problem (measured)

| Fact | Value | Source |
| --- | --- | --- |
| Slice ceiling | `MemoryMax=18GiB`, `MemorySwapMax=4GiB`, `ManagedOOMMemoryPressure=auto` | `systemctl --user show harness.slice` |
| Current usage | 17.8 G / 18 G; fat scope `run-p2315788` 17.2 G (5h48m), thin `run-p4047791` 1.07 G | `systemctl show` / `memory.current` |
| Fat main process RSS | 9.04 GiB | `/proc/2315788/smaps_rollup` |
| Heap composition | `[anon]` 5.0 G, `[anon:WKFastMalloc]` 2.34 G, `[anon:JSGigacage]` 1.54 G, `[heap]` 34 M | `smaps` by-mapping |
| Cgroup breakdown (fat scope) | anon 9.95 G, file 5.31 G (reclaimable), kernel 0.81 G, shmem 3.29 G | `memory.stat` |
| Prior kills | 4× `Killed process (nocowboy)` at anon-rss 5.13 / 8.94 / 4.23 G, `oom_score_adj=900` | `journalctl -k`; slice `memory.events` `oom_kill=4` |

**Root cause is application-level heap growth in a Bun/JavaScriptCore TUI, not the OOM policy and not language servers** (svelteserver 236 M, bash-LS 150 M, 8× eslint 50–70 M — negligible). The heap grows monotonically with session age and reaches ~9 GiB at ~6 h. Two instances share one 18 GiB slice, so a single mature instance consumes the entire budget and starves the second — the current no-per-scope-cap bug.

### Root-cause retention points in the app source (`/home/ldco/nocowboy-backup/app-worktree`)

1. **TUI timeline keeps every part of the live session in RAM** — `packages/app/src/state/timeline.ts:86–227`. `SessionTimeline` holds `#parts: Map<string, PartView>` where each `PartView` retains `tool.output` and full `text`; `apply()` appends every `message.updated`/`part.updated`/`part.delta` and never evicts. A 6 h agentic session accumulates thousands of parts. 🟢 code-read.
2. **Compaction clones and snapshots the full head** — `packages/opencode/src/session/compaction.ts:437` (`structuredClone(selected.head)` on every compaction) and `:654–677` (`SessionExport.compaction` with `selectedContext: selected.head`). 🟢
3. **`prune` does not release output** — `compaction.ts:326–375` sets `part.state.time.compacted = Date.now()` but leaves `part.state.output` attached; compacted tool output stays referenced in RAM and DB. 🟢
4. **Full-session materialization per turn** — `packages/opencode/src/session/session.ts:829–848` (`messages()` pages the whole session into a JS array on each turn). 🟢
5. **Ruled out as the leak** 🟢: SQLite page cache (`storage/db.ts:120`, `cache_size=-64000` → 64 MiB bounded); sync event store (`sync/index.ts:317–415`, events go to SQLite, projector maps are bounded definitions); per-part tool output is already truncated to 2 000 lines / 50 KiB and spilled to disk (`tool/truncate.ts:16–17,86–142`, `prompt.ts:786–796` stores `output: truncated.content`). The unbounded quantity is the **number of retained parts**, not any single part's size.

The `[anon]` 5.0 G + `WKFastMalloc` 2.34 G (WTF containers) + `JSGigacage` 1.54 G (JSC typed arrays) decomposition is consistent with an unbounded JS object graph of strings and buffers — the timeline + full-history-snapshot pattern. Exact attribution of the 5 G anon requires a Bun heap snapshot; that is the acceptance proof for L0, not a pre-requisite for this ADR. 🟡 inference.

## Decision — four layers, ordered by what actually prevents the crash

| Layer | What | Mandatory for "never crash"? | Belongs to |
| --- | --- | --- | --- |
| **L0** | App-level bounded retention: window the timeline, release compacted output, stop cloning the full head | **Yes — the only true fix** | nocowboy app repo |
| **L1** | Per-scope `MemoryMax=9GiB` / `MemorySwapMax=2GiB` | **Yes — fairness (fixes the current starvation bug)** | this repo |
| **L2** | Graceful supervisor: SIGTERM at threshold → checkpoint → respawn with session resume | Yes — converts residual kill into clean restart | this repo + app (SIGTERM handler) |
| **L3** | App-level backpressure: self-monitor anon, compact/GC/pause before the threshold | Makes L2 rare; is the user's "slow down" | nocowboy app repo |

Ordering rationale: **L0 + L1 are the fix; L2 + L3 make the residual non-fatal and self-healing.** Per-scope cap alone (L1) only moves the kill from 18 G to 9 G — the observed 9.04 GiB instance already reaches that wall, so without L0 the app still dies. Raising the slice ceiling is rejected (see below); the host cannot fit two 9 G instances plus the desktop.

## Numbers (derived from this machine)

Host: **30.9 GiB** RAM, 62.9 GiB swap (31 GiB zram prio 100 + 32 GiB file prio −1) — `oomctl`, `swapon`.

| Parameter | Value | Derivation |
| --- | --- | --- |
| Desktop reservation | ≥ 11 GiB | `OOM-WEZTERM.md:94`; observed Plasma+kwin+WezTerm+browsers ≈ 7–8 GiB |
| `harness.slice` `MemoryMax` | **18 GiB (unchanged)** | 30.9 − 11 − ~2 slack; the honest harness ceiling |
| `harness.slice` `MemorySwapMax` | 4 GiB (unchanged) | zram grace for spikes |
| **Per-scope `MemoryMax`** | **9 GiB** | 18 ÷ 2 instances (was: *unlimited* — one scope could eat all 18) |
| **Per-scope `MemorySwapMax`** | **2 GiB** | 4 ÷ 2 |
| L0 target RSS per instance | ≤ 6 GiB | 2 × 6 = 12 GiB, 6 GiB headroom inside the 18 GiB slice |
| Backpressure (soft) threshold | 6 GiB anon | = L0 ceiling; triggers L3 before any restart |
| Graceful (SIGTERM) threshold | 7.6 GiB anon | ≈ 85 % of the 9 GiB per-scope cap; leaves ~1.4 GiB to flush |
| Hard cap (kernel OOM) | 9 GiB / scope, 18 GiB / slice | last-resort backstop only |

Arithmetic after L0: two instances at 6 GiB = 12 GiB < 18 GiB slice, desktop has 18.9 GiB free. Worst case (both at the 7.6 GiB graceful threshold) = 15.2 GiB < 18 GiB. The 18 GiB slice is reached **only** if both instances ignore SIGTERM at 7.6 GiB — the exact failure L2 makes non-fatal.

## Backpressure — "slow down, make time to regenerate"

Two distinct mechanisms, and only one survives the measurement:

- **Kernel `memory.high` throttling — rejected.** Measured to livelock: a 16 GiB soft limit plates the allocator at 16.4–16.6 GiB for ~8 minutes without reaching the 18 GiB cap and without OOM (`OOM-WEZTERM.md:95`). Kernel throttling stalls allocations; it does not give a JSC TUI a chance to compact, because the app is not signal-aware. "Slow down" ≠ "freeze".
- **App-level backpressure — accepted.** The app reads its own cgroup anon on a periodic tick (the codebase already runs periodic effect loops, e.g. `snapshot/index.ts:846–854` hourly cleanup). Above 6 GiB anon it: triggers compaction (reuses `IdleCompaction`, `compaction.ts`), releases compacted `part.state.output` bodies, calls `Bun.gc()`, and pauses background goals/roadmap/autopilot. It then resumes. This is the user's "make time to regenerate": the app sheds and reclaims instead of being throttled. **Who triggers it: the app self-monitors** — the kernel cannot trigger app-level compaction. Feasibility 🟢: the compaction machinery and periodic-loop pattern already exist.

## Graceful path (L2) — exact contract

| Step | Detail |
| --- | --- |
| Watchdog location | `scripts/tools/harness-run.sh` — a small loop inside the scope (inherits `oom_score_adj=900`, tiny) |
| Signal measured | **anon** from `memory.stat`, *not* `memory.current` — the fat scope's 5.31 G of reclaimable file cache must not trigger a false restart |
| Threshold | 7.6 GiB anon (85 % of the 9 GiB per-scope cap) |
| Action | `SIGTERM` (never SIGKILL) to the nocowboy pid |
| App contract on SIGTERM | flush SQLite WAL, record the active session id to `~/.local/state/nocowboy/last-session`, exit 0 (sessions are already persisted per-part; `cli/cmd/run.ts:159–175,391` already supports `--continue` / `--session <id>` / `resume`). Confidence on the TUI entry accepting `--session` like `run.ts`: 🟡 — needs a one-line verification; the headless `run --session` path is 🟢 |
| Respawn | launcher loop re-execs `nocowboy --continue` (or `--session <id>`), reattaching the persisted session |
| Proof of clean exit | new scope exits `Result=exit-code` 0 with no `oom_kill` in `memory.events`; `journalctl -k` shows no `Killed process (nocowboy)` for that scope |

## Rejected alternatives (each with its measurement)

| Option | Why rejected |
| --- | --- |
| `MemoryHigh` soft limit / kernel throttling | Liveloes: 16 G soft limit plates at 16.4–16.6 G for ~8 min, never reaches 18 G, no OOM — `OOM-WEZTERM.md:95` |
| Raise the slice cap (22–24 G) | 30.9 G host − 22 G harness < 11 G desktop reserve; starves the compositor, postpones the 9 G-growth kill (`OOM-WEZTERM.md:55–58`) |
| More swap / zram backing device | Swap was never short (5.7/62.9 G at the incident, 14.6 G now); root-level boot config; symptom, not the 9 G anon growth (`OOM-WEZTERM.md:144,201–204`) |
| Disable systemd-oomd / edit `user@1000` | Wrong layer — the kill is the kernel cgroup OOM, not oomd; trades a killed harness for a thrashed machine (`OOM-WEZTERM.md:143`) |
| Per-scope cap alone (no L0) | Moves the kill from 18 G to 9 G; the observed 9.04 GiB instance already hits it — still a SIGKILL |
| Only the graceful supervisor (no L0) | Restart becomes so frequent (every ~6 h × 2 tabs) the session is barely usable; supervisor is a safety net, not a growth-removal strategy |

## Consequences

- **Positive:** the harness never dies by SIGKILL in normal operation; a mature instance recycles below 6 GiB (L0/L3), or exits cleanly and resumes (L2); two tabs run concurrently within a 12 GiB working budget; terminal/compositor protection from `OOM-WEZTERM.md` is unchanged.
- **Cost:** L0/L3 are app-repo changes with real surface (timeline windowing, prune release, full-head clone removal, a memory-pressure tick); L1/L2 are small launcher changes. L0 requires a heap-snapshot verification pass (1 h / 3 h / 6 h) before it is accepted — the price of "prove it no longer grows".
- **Residual risk (accepted, documented):** a single pathological tool call that materializes > 9 GiB in one shot still hits the per-scope cap; the 7.6 → 9 GiB window (~1.4 GiB) is sized for a checkpoint, not for a runaway allocator.

## Ownership split

| Change | Repo / file |
| --- | --- |
| Timeline windowing + hydrate-on-scroll | nocowboy app — `packages/app/src/state/timeline.ts` |
| Prune releases `output`; drop `structuredClone(head)`; stream `SessionExport` | nocowboy app — `packages/opencode/src/session/compaction.ts`, `nocowboy/session-export*` |
| Cgroup anon self-monitor tick (L3) | nocowboy app — new module, e.g. `packages/opencode/src/nocowboy/memory-guard.ts` |
| SIGTERM handler: checkpoint + record session id + exit 0 | nocowboy app — TUI entry / runtime |
| Per-scope `-p MemoryMax=9G -p MemorySwapMax=2G` | **this repo** — `scripts/tools/harness-run.sh` |
| SIGTERM watchdog + respawn loop (L2) | **this repo** — `scripts/tools/harness-run.sh` |
| Slice constants / comments | **this repo** — `scripts/tools/oom-guard.sh` |
| ADR + cross-ref from `OOM-WEZTERM.md` | **this repo** — `docs/ADR-harness-memory.md`, `docs/OOM-WEZTERM.md` |

## Acceptance criteria

1. A 6 h+ two-instance run produces **zero** `Memory cgroup out of memory: Killed process … (nocowboy)` journal lines.
2. Degradation is a clean `SIGTERM` → exit 0 → `nocowboy --session <id>` resume, proven by journal lines and `systemctl --user show <scope> -p MemoryMax,MemoryPeak` (peak ≤ 9 GiB, `memory.events oom_kill = 0`).
3. Per-instance isolation: forcing one scope to 9 GiB leaves the sibling scope's `memory.events` all-zero.
4. Every number above traces to a `systemctl show` / `memory.stat` / `journalctl` line; every rejected option carries its measurement.
5. Heap snapshots at 1/3/6 h show a live instance ≤ 6 GiB RSS (L0 verified), not merely capped at 9 GiB.

**Verdict:** the crash is an app-level heap-growth bug, not an OOM-policy bug. L0 (bounded retention) + L1 (per-scope 9 G) are the fix; L2 (SIGTERM→resume) + L3 (self-monitor backpressure) make the residual overflow non-fatal and self-healing — the "slow down and regenerate instead of crash" the user asked for.
