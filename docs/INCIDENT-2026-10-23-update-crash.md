# INCIDENT 2026-10-23 — interrupted full upgrade + snapper-tools restore

Status: **diagnosed**, system currently on the last good (pre-update) root.
Author: NoCowboy (auto), 2026-10-23 16:45 MSK.

## TL;DR

* `/` was **not** rolled back to an old snapshot. It is today's pre-update state (13:25–13:27 MSK).
* The full upgrade (`pacman -Su --noconfirm`, 677 packages pending) **never finished**: 206
  operations were applied, then the log stops at `13:28:29` — `transaction completed` is absent.
* The machine hard-froze at ~13:31–13:55 (kwin hung; journal ends), was rebooted at 13:56,
  and the user restored via **snapper-tools GUI** twice:
  * `13:57:13` — old root renamed to `@_backup_20262310135713017` (the half-updated root)
  * `14:07:10` — root renamed to `@_backup_20262310140710460` (first restore result)
* Result: current `/` = pre-update root from snapshot 287 lineage (13:27:28).
* **No user data lost.** `/home`, `/root`, `/srv`, `/var/log`, `/var/cache` are separate
  subvolumes and were never part of the rollback.
* There is nothing to "restore back to": the fully-updated system never existed. To reach the
  latest version, the upgrade must be re-run — from a TTY, without a running Plasma session.

## Verified current state

| Item | Value | Evidence |
|---|---|---|
| Live root subvolume | `id 552`, path `/@` | `findmnt`, `btrfs inspect-internal rootid /` |
| `/home` | `id 257` (original install) | untouched |
| `/root` | `id 258` | untouched |
| `/var/log` | `id 261` (@log) | pacman.log retains the crashed transaction |
| `/var/cache` | `id 260` (@cache) | downloaded packages survive the rollback |
| Root mtime | `2026-10-23 14:07:10` | rename of `@` → `@_backup_20262310140710460` |
| android-studio | `2026.2.1.8-2.1` | updated today 10:14, present in live root |
| chaotic-mirrorlist mtime | `13:25:33` | matches snapshots 285/286/287 |
| plasma-desktop | `6.7.5` | pre-update (pending: 6.8.1) |
| qt6-base | `6.11.2` | pre-update |
| llvm-libs | `22.1.8` | pre-update (crashed run installed 23.1.3) |
| ministream / clang-libs / llvm-lit | absent | installed at 13:28:15–19, gone after rollback |
| kernel | `linux-zen 7.2.7` | `/boot` files dated 2026-09-27 |
| pending upgrades | 677 (`pacman -Qu`) | against the 13:27 sync DB |

Snapshots (btrfs ids): 275→538, 276→539, 277→540, 278→541, 279→542, 280→543,
281→544, 282→545, 283→546, 284→547, 285→548, 286→549, **287→550**.

## Timeline (MSK)

| Time | Event |
|---|---|
| 03:11 | `garuda-update` started (no transaction completed) |
| 09:21 | `pacman -Su --config /tmp/...` started (no transaction completed) |
| 10:11–10:14 | android-studio upgraded → snapshots 281–284 |
| 10:19 | `pacman -Su` started, hung/interrupted |
| 13:24–13:25 | `DisableDownloadTimeout` patched into `/etc/pacman.conf`; `.part` files deleted; mirrorlist rewritten |
| 13:25:37–40 | chaotic-mirrorlist reinstall → snapshots 285/286 |
| **13:27:28** | **snapshot 287 (pre) — `pacman -Su --noconfirm` begins** |
| 13:27:38 | transaction started |
| 13:28:15–19 | clang-libs 23.1.3, llvm-lit, llvm 23.1.3, gtk4 1:4.24.1, ministream installed |
| 13:28:24 | `kded6`: plugin uses incompatible Qt library (6.12.0) — mid-update mismatch |
| **13:28:29** | **last log line (`breeze-cursors`); transaction never completed** |
| 13:31:39 | `kwin_wayland`: "The main thread was hanging temporarily!" |
| ~13:47–13:55 | journal ends; machine hard-froze; power cycle |
| 13:56:05 | boot (1 min) |
| 13:57:13 | snapper-tools restore #1: `@` → `@_backup_20262310135713017` |
| 13:58:33 | boot into restored root |
| 14:05–14:07 | snapper-tools GUI opened again (`--confirm-restore`) |
| **14:07:10** | **restore #2: `@` → `@_backup_20262310140710460`; new `@` = snapshot 287 lineage (id 552)** |
| 14:07:29 | shutdown |
| 16:29 | current boot |

## Recovery runbook

### 0. Verify the backup subvolumes still exist (root required)

```bash
sudo btrfs subvolume list / | grep -E '@_backup|/@$|\.snapshots'
```

Expected: `@` (552), `@_backup_20262310135713017` (half-updated root — **do not boot**),
`@_backup_20262310140710460` (first restore).

### A. Stay on the current root — recommended

Nothing to do. This is the last consistent state (pre-update). Verify:

```bash
findmnt -no SOURCE,OPTIONS /
pacman -Q plasma-desktop qt6-base llvm-libs android-studio
grep -c 'transaction completed' /var/log/pacman.log   # last entry must predate 13:27
```

### B. Inspect the half-updated root read-only (do not boot it)

```bash
sudo mkdir -p /mnt/oldroot
sudo mount -o subvol=@_backup_20262310135713017,ro \
  /dev/mapper/luks-a1e58895-593e-4712-9c73-9b3d064ccfcb /mnt/oldroot
# compare / diff anything you need
sudo umount /mnt/oldroot
```

It contains the 206 applied operations (llvm 23, qt 6.12, plasma 6.8.1, …) in an
inconsistent mid-transaction state — useful only for inspection.

### C. Finish the upgrade safely (to reach "latest")

The crashed run died with a live Plasma session while Qt/Plasma were being replaced.
Rule: **never run a full upgrade from inside a running graphical session.**

```bash
# 1. extra safety snapshot
sudo snapper create -d "before-update-retry"

# 2. leave the GUI — log out of Plasma, then Ctrl+Alt+F3 and log in on tty3
sudo systemctl isolate multi-user.target    # optional: kills the GUI session

# 3. run the upgrade (packages are already in @cache, so it is mostly local)
sudo pacman -Syu --noconfirm

# 4. proof of completion
grep 'transaction completed' /var/log/pacman.log | tail -1
sudo reboot
```

If it fails again at the same point, boot snapshot **287** from the grub-btrfs menu
(proven good), then bisect the transaction (`sudo pacman -Su --print`, install in groups).

### D. Cleanup — only after a successful upgrade and one clean reboot

```bash
sudo btrfs subvolume delete /path/to/top-level/@_backup_20262310135713017
sudo btrfs subvolume delete /path/to/top-level/@_backup_20262310140710460
```

(the backups are COW, so keeping them costs little until data diverges).

## Prevention

1. Run `garuda-update`/`pacman -Syu` from a TTY, never from a live Plasma session.
2. For very large pending sets (677 here), update in stages or at least with the GUI stopped.
3. Keep snapshots (snap-pac already does pre/post) and verify `transaction completed`
   in `/var/log/pacman.log` before rebooting.
4. `@_backup_*` subvolumes are not managed by snapper cleanup and will not be removed
   automatically — they are the manual escape hatch.

---

## 2026-10-23 17:20 — why every retry failed, and the prepared state

The upgrade was retried end-to-end in a controlled way. The recurring
"error about some app or another" had four distinct causes:

1. **Broken first mirror.** `wan.metrosg.ru` — the first `Server` in
   `/etc/pacman.d/mirrorlist` — answers **HTTP 403** for `core.db`.
2. **Flaky chaotic-aur mirrors.** `cdn-mirror.chaotic.cx` needed >15 s to
   answer and `geo/us/de` occasionally returned 404 for freshly rebuilt
   packages (`vectorcraft`, `brave-bin`, `google-chrome`). Pacman downloads
   **all** packages before installing, so a single 404 aborts the whole
   transaction: `failed to retrieve some files` / `no packages were upgraded`.
   The package named in the error is effectively random.
3. **Unsatisfiable dependency.** `balena-etcher 2.1.6-1` requires
   `nodejs-lts-jod`, which conflicts with `nodejs 26.10.0` — itself required by
   `npm`, `yarn`, `zed`, `cursor-bin`. `pacman -Dk` reported the local DB as
   broken. `balena-etcher` was removed (unused; it bundles its own Electron).
4. **Wrong place to install.** The pending set replaces Plasma 6.7→6.8, Qt
   6.11→6.12, Mesa and every Vulkan package, the NVIDIA driver and the kernel.
   Installing that under the live compositor is what hung `kwin` and froze the
   machine.

### What was done

| Change | Evidence |
|---|---|
| `pacman.conf`: exactly one `DisableDownloadTimeout` | `grep -c` → 1 |
| Mirrorlists re-ranked by `rate-mirrors` | 60 Arch + 10 chaotic-aur servers |
| Config backups | `/var/backups/garuda-restore/system-update-20261023-170941/` |
| `balena-etcher` removed | `pacman -Rns balena-etcher`; `pacman -Dk` → clean |
| Pre-update snapshot | snapper `290`, `before-update-20261023-171438`, `important=yes` |
| All 679 packages downloaded | `pacman -Syu --downloadonly` → success |
| Safe update tooling | `scripts/tools/update-engine.sh`, rewritten `scripts/tools/system-update.sh` |
| Runbook | `docs/UPDATES.md` |

### Remaining step — install from a text console

The packages are cached, so this is local and fast. It must not run from
Plasma (the front-end now refuses):

```bash
# Ctrl+Alt+F3, log in
sudo systemctl isolate multi-user.target
sudo /run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb/LinuxDCO/garuda-restore/scripts/tools/update-engine.sh install --aur
sudo reboot
```

Success criterion (checked automatically by the engine):

```bash
grep 'transaction completed' /var/log/pacman.log | tail -1   # must be after 17:20
pacman -Qu | wc -l                                           # repo updates: 0
```

If it fails again, do **not** reboot blindly: boot snapshot 290 from the
grub-btrfs menu and read `/var/log/garuda/system-update-*.log`.

---

## 2026-10-23 17:50 — why `update-now.sh` showed a black screen

The first `update-now.sh` run (17:37) did not install anything. Journal:

```
17:37:05 Started [systemd-run] .../update-engine.sh install --force --offline
17:38:05 garuda-update-now.timer: Deactivated successfully
17:38:05 Stopped [systemd-run] .../update-engine.sh install --force --offline
17:38:15 user session shutdown (isolate multi-user.target)
```

`systemctl isolate` stops every unit that is not part of the new target. A
transient unit created by `systemd-run` is not in `multi-user.target`, so the
isolate killed it in the same second the timer fired. The engine never reached
`setup_logging` — there is no `system-update-*.log` after 17:15. The screen was
black because the active VT was the dead Plasma tty; the console was on tty1.

Fixes in `update-now.sh`:

- `--property=IgnoreOnIsolate=yes` on the transient unit;
- `chvt 1` before the isolate;
- runner starts after the countdown, waits 10 s for the session to stop;
- on success: automatic reboot; on failure: `systemctl start graphical.target`
  and the error is printed to the console.

Verified after the failed run: 679 packages still pending, `pacman -Dk` clean,
no package replaced.
