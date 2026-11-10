# System updates (Garuda / Arch)

Status: **active runbook** — created 2026-10-23 after the third failed attempt
to install 679 pending packages.

## Is a TTY required for every update?

**No.** There is no Arch or KDE rule that packages must be installed from a
text console. The Arch Wiki only states that upgrades are not applied to
running processes and that a reboot is the most secure way to finish
([System maintenance § Restart or reboot after upgrades](https://wiki.archlinux.org/title/System_maintenance#Restart_or_reboot_after_upgrades)).
Garuda recommends `garuda-update` and normally it runs fine from Konsole.

The offline/TTY step is for one case only: when the transaction replaces the
**running** desktop and graphics stack. The 2026-10-23 update was 679 packages
including Plasma 6.7→6.8, Qt 6.11→6.12, KIO/KF6, Mesa, Vulkan, NVIDIA and the
kernel. `kded6` loaded a KIO plugin built for Qt 6.12 while still running
Qt 6.11; kwin hung. Ordinary weekly updates are fine from a terminal emulator.

## TL;DR

```bash
# 1. While the desktop is running (downloads only, installs nothing)
sudo ./scripts/tools/update-engine.sh prepare

# 2. Install it: verifies the staged cache, stops the desktop, installs from
#    the cache as a system unit, reboots on success
sudo ./scripts/tools/update-now.sh

# 3. After one clean boot, prune the cache
sudo ./scripts/tools/update-engine.sh clean
```

`update-now.sh --dry-run` runs every check without touching the desktop.

`./scripts/tools/system-update.sh` is the interactive front-end: it runs phase 1
automatically when it detects a graphical session and phase 2 when it does not.
It also performs the usual maintenance (dev caches, orphan review, journal).

## Why a two-phase update

On 2026-10-23 a 677-package upgrade was started from a live Plasma session
(`pacman -Su`). It installed 206 packages, the compositor hung while Qt/Plasma/
Mesa/NVIDIA were being replaced, and the machine froze mid-transaction. The
half-updated root had to be rolled back from snapshot 287.

The pending set replaces the whole graphics stack:

- `plasma-desktop` 6.7.5 → 6.8.1, `qt6-base` 6.11.2 → 6.12.0
- `mesa` 26.2.3 → 26.2.5, every `vulkan-*` package
- `nvidia-open-dkms` / `nvidia-utils` 615.71 → 615.78
- `linux-zen` 7.2.7 → 7.2.11, `systemd` 262 → 262.1

Installing that from inside the session it is replacing is unsafe. Downloading
is safe; installing is not.

## Why "some app or another" kept failing

`pacman` downloads every package **before** starting the transaction. One
failed download aborts the whole upgrade with `failed to retrieve some files`
and `no packages were upgraded` — the package named in the error is random.

Two concrete causes found:

1. The first Arch mirror in `mirrorlist` (`wan.metrosg.ru`) returned HTTP 403
   for `core.db`, and several chaotic-aur mirrors timed out or 404'd for
   packages that had just been rebuilt (`vectorcraft`, `brave-bin`,
   `google-chrome`). The 13:25 mirrorlist rewrite had left a stale order.
2. `balena-etcher` 2.1.6-1 required `nodejs-lts-jod`, which conflicts with the
   installed `nodejs` 26.10.0 (required by npm, yarn, zed, cursor). A missing
   dependency made `pacman -Dk` dirty. The package was removed; it bundles its
   own Electron runtime and was never used on this machine.

`prepare` fixes both: `rate-mirrors` ranks and validates the mirrorlists, the
local DB is checked with `pacman -Dk`, and downloads are retried up to 10 times
(refreshing the databases every third attempt).

## What prepare does

1. Backs up `/etc/pacman.conf` and both mirrorlists to
   `/var/backups/garuda-restore/system-update-<timestamp>/`.
2. Normalises exactly one `DisableDownloadTimeout` entry.
3. Refreshes `mirrorlist` and `chaotic-mirrorlist` with `rate-mirrors`
   (≥10 Arch servers, ≥4 chaotic-aur servers, otherwise keeps the old list).
4. `pacman -Syy`, then `pacman -Dk`; resolves the known `balena-etcher`
   dependency conflict.
5. Creates a snapper snapshot (`before-update-*`, `important=yes`).
6. `pacman -Syu --downloadonly` with retries — no package is installed.
7. Verifies that every upgrade target is really in the cache and writes the
   staging manifest `/var/lib/garuda-restore/staged.manifest` (target list and
   its sha256) — the proof that the cache-based install can run.
8. Prints the next step (`update-now.sh`).

## Without typing in a TTY: one command from Konsole

The upgrade replaces the compositor you are typing in, so it cannot run as a
child of that session:

```bash
sudo ./scripts/tools/update-now.sh
```

1. **verifies the staged cache first** — read only, network free, ~1 s
   (`update-engine.sh install --offline --check-cache`). An incomplete or
   stale cache refuses **before** anything is touched, and nothing is
   downloaded: this is what prevents the 2026-11-10 run, where `pacman -Sc`
   had purged the staged 8.7 GiB and the "offline" install re-downloaded all
   of it on tty1;
2. copies the engine and the runner to `/usr/local/lib/garuda-restore/`
   (independent of this repo and the external drive);
3. installs `systemd/garuda-update-now.service` and starts it;
4. the unit declares **`Conflicts=graphical.target`** + **`After=graphical.target`**,
   so the desktop is stopped as a dependency effect and the install begins
   only after Plasma is gone;
5. pid 1 owns the runner, so the graphical teardown cannot stop it. The old
   design used a transient `systemd-run` unit and lost the race **twice** —
   2026-10-23 17:38 and 2026-11-11 00:51, when the unit was "Deactivated
   successfully" five seconds in and installed nothing;
6. the runner installs offline from `/var/cache/pacman/pkg` with **no
   `--force`**: if a compositor is somehow still alive, the engine refuses and
   the desktop comes back instead of replacing Qt under a dying Plasma;
7. **reboots automatically on success**; on failure it starts
   `graphical.target` again, so the desktop returns instead of leaving a black
   screen.

**Nothing to log in to and nothing to type.** The runner takes tty1 over —
`getty@tty1` is stopped, so there is no login prompt — and mirrors every line
to that screen, to the journal and to `/var/log/garuda/update-now-run.log`
(`tee` to three sinks, fd 3 keeps the journal). Progress is pacman's own
per-package output; the screen does not blank (`setterm --blank 0`).

Start it, leave the machine alone, come back to a rebooted system. On failure
the desktop comes back by itself and `garuda-update-restore.service` posts a
desktop notification:

```bash
journalctl -u garuda-update-now          # the whole run, afterwards
```

If the console is somehow unavailable, the journal and the transcript hold the
same output.

`sudo ./scripts/tools/update-now.sh --dry-run` runs the checks and prints the
unit it would start, without stopping anything.

AUR packages are not touched in this mode; run `paru -Sua` after the reboot.

## One command after an update: `stabilize-once.sh`

```bash
sudo ./scripts/tools/stabilize-once.sh          # idempotent, safe to re-run
./scripts/tools/stabilize-once.sh --dry-run     # plan only, no root
```

It closes everything that is still manual once an upgrade has landed:

1. installs and enables the weekly stack — `update-prepare.timer` (Friday
   21:55 staging), `update-prompt.timer` (reminders), `update-maintenance.service`
   — and enables `grub-btrfsd` so a fresh snapshot reaches the GRUB menu without
   waiting for a `grub-mkconfig`;
2. merges `/etc/paru.conf.pacnew` and enables `MinimumReleaseAge = 3d`
   (paru refuses AUR packages modified in the last three days — a delay, not an
   `IgnorePkg` pin, so no partial-upgrade risk);
3. runs the maintenance now: cache prune (`KEEP_PACKAGES` versions), journal
   vacuum, `fstrim`, orphan list, `garuda-health` report;
4. removes pacman's stale `download-*` temp dirs left by aborted downloads;
5. verifies timers, guards (PL1, quota, sleep mask, snapshot plumbing), pending
   updates and disk, then prints what stays manual (AUR, LTS boot test, sleep).

`install-update-timer.sh` had its unit sources pointing at `scripts/systemd`
(nonexistent), so under `set -e` it died on the first `install` and **none of
the timer units had ever been installed**. That is fixed, and the test suite now
asserts that every unit source it references exists.

## When something fails, you are told

All three update units carry `OnFailure=garuda-update-alarm@%n.service`. A failed
Friday staging, a failed reminder or a failed install therefore:

- appends `systemctl status` output to `/var/lib/garuda-restore/alerts.log`,
- broadcasts a line to every tty,
- posts a critical desktop notification to the active session,

at most once per hour per unit, so a repeated failure cannot become a storm. The
old behaviour was silence: the evidence sat in a log until somebody looked.

`IgnoreOnIsolate=yes` was in `[Service]` in `update-prepare.service` and
`update-prompt.service`, where systemd ignores it - a `systemctl isolate` could
stop a staging run mid-execution. It is a `[Unit]` key and now sits there.

## Running the pieces by hand

```bash
# Total maintenance and cleanup, at any time (no update needed):
sudo ./scripts/tools/maintenance-run.sh --now
#   cache prune (KEEP_PACKAGES versions) + journal vacuum + fstrim +
#   orphan list + garuda-health report; output on the terminal and in
#   /var/log/garuda/update-maintenance.log

# The Friday staging job, by hand (downloads only, the desktop stays usable):
sudo ./scripts/tools/update-engine.sh prepare

# The same staging through the timer's own path, including the GUI prompt:
sudo systemctl start update-prepare.service
```

`--now` is what the system runs automatically on the first boot after an
applied update; it skips the "post-update flag" check so it can be used as a
routine cleanup. Orphans are listed, not removed (`REMOVE_ORPHANS=0`), because
some of them are user-facing (KWin effects, themes, language tooling).

## What install does

1. Refuses if an active Wayland/X11 session exists (`--force` overrides it —
   the automated path never uses `--force`).
2. `--offline`: verifies the staging manifest and **every package file** in
   `/var/cache/pacman/pkg`, and never touches the network. An incomplete
   cache fails in about a second and lists the missing packages. Without
   `--offline` the missing packages are downloaded first.
3. Runs `garuda-update --skip-mirrorlist --noconfirm [--aur]`
   (`GARUDA_SLEEP_INHIBIT=1` in offline mode: no DB sync, no self-update).
4. Requires a new `transaction completed` line in `/var/log/pacman.log`.
   If it is absent, the upgrade did not finish — **do not reboot blindly**.
5. In offline mode, audits its own log for `downloading ` lines and warns if
   the run fetched anything, so the "offline" claim is verifiable after the
   fact.

Logs:

- `/var/log/garuda/system-update-<timestamp>.log` — this tool
- `/var/log/garuda/update-now-run.log` — full transcript of an unattended run
  (overwritten per run; the previous one is kept as `.1` past 5 MB)
- `journalctl -u garuda-update-now` — the unit's own output
- `/var/log/garuda/garuda-update` — the update itself
- `/var/log/pacman.log` — authoritative transaction record

## Troubleshooting

- **`graphical session is active`** — either run `sudo ./scripts/tools/update-now.sh`
  (it stops the GUI and detaches the transaction), or
  `sudo systemctl isolate multi-user.target` and rerun `install`.
- **`FATAL: the staged package cache is incomplete or stale`** — the desktop
  was not stopped and nothing was downloaded. Rerun
  `sudo ./scripts/tools/update-engine.sh prepare`, then `update-now.sh`.
- **`pacman -Sc` destroys a staged update** — 2026-11-10: `prepare` had staged
  8.7 GiB (449 packages), a `sudo pacman -Sc` later deleted every cached file
  that was not the installed version, and the install attempt had to download
  everything again. Never prune the cache between `prepare` and `install`.
- **`Nothing to install`** — no repo upgrades are staged; the desktop was not
  stopped.
- **The desktop did not come back after a failed install** — it should, by
  itself (`garuda-update-restore.service`): it starts `graphical.target`, waits
  for the session and posts a notification. If it did not, Ctrl+Alt+F1,
  `journalctl -b -u garuda-update-now -u garuda-update-restore` and
  `sudo systemctl start graphical.target`. The engine refuses to install while
  a compositor is alive, so a leftover `kwin_wayland` is the usual cause.
- **`garuda-update-now.service` is skipped ("condition failed")** — the
  request flag `/var/lib/garuda-restore/update-now.request` is missing. Start
  the install with `update-now.sh`; never by `systemctl start` alone.
- **Download failures during prepare** — rerun `prepare --skip-mirrors`
  (mirrors are already ranked); the loop resumes from the cache.
- **Transaction fails at the same package every time** — inspect the error in
  `/var/log/garuda/system-update-*.log`; if it is a genuine conflict, fix it
  before retrying, do not loop.
- **No `transaction completed`** — the system may be mid-transaction. Boot the
  pre-update snapshot from the grub-btrfs menu (snapshot 290 from 2026-10-23
  17:14, or the latest `before-update-*`) via snapper-tools, then diagnose.
- **Keyboard/console** — on this laptop Ctrl+Alt+F3 is a text console; return to
  the desktop with Ctrl+Alt+F2 (Plasma is on tty2 here).
