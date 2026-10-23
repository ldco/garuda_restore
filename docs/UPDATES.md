# System updates (Garuda / Arch)

Status: **active runbook** — created 2026-10-23 after the third failed attempt
to install 679 pending packages.

## TL;DR

```bash
# 1. While the desktop is running (downloads only, installs nothing)
sudo ./scripts/tools/update-engine.sh prepare

# 2. Save work, switch to a text console: Ctrl+Alt+F3, log in
sudo systemctl isolate multi-user.target
sudo ./scripts/tools/update-engine.sh install --aur

# 3. Reboot and, after one clean boot, prune the cache
sudo reboot
sudo ./scripts/tools/update-engine.sh clean
```

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
7. Prints the remaining TTY steps.

## What install does

1. Refuses if an active Wayland/X11 session exists (`--force` overrides).
2. Verifies the cache is complete (`pacman -Su --downloadonly`).
3. Runs `garuda-update --skip-mirrorlist --noconfirm [--aur]`.
4. Requires a new `transaction completed` line in `/var/log/pacman.log`.
   If it is absent, the upgrade did not finish — **do not reboot blindly**.

Logs:

- `/var/log/garuda/system-update-<timestamp>.log` — this tool
- `/var/log/garuda/garuda-update` — the update itself
- `/var/log/pacman.log` — authoritative transaction record

## Troubleshooting

- **`graphical session is active`** — `sudo systemctl isolate multi-user.target`,
  then rerun `install`.
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
