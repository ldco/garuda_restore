# Restore Script — Comprehensive Fix Plan

## Audit Findings (Fresh Install → Restore Timeline)

### Root Cause
`restore.sh` step 4 concatenated all 382 packages into ONE `pacman -S` command via `tr '\n' ' '`. AUR-only packages (davinci-resolve, happ-desktop-bin, nocowboy, ypn-client) in the explicit list caused pacman to fail silently (`|| true`). 84 of 382 packages were never installed.

### All Manual Interventions Discovered

| # | Intervention | When | Why |
|---|-------------|------|-----|
| 1 | Batch pacman retry with ~50 packages | Jun 29 21:05 | First batch failed |
| 2 | `pacman -Rdd nodejs-lts-jod` | Jun 29 21:07 | npm conflict blocking packages |
| 3 | `pacman -Sy chaotic-keyring chaotic-mirrorlist` | Jun 29 21:10 | GPG key issues |
| 4 | `pacman-key --init && pacman-key --populate` | Jun 29 ~22:00 | GPG trust DB corruption |
| 5 | 80+ one-at-a-time pacman installs | Jun 29 23:50 | Batch install kept failing |
| 6 | KDE data restore (icons, plasma, aurorae, color-schemes) | Jun 29 21:25 | Config restore from backup |
| 7 | `gtk-update-icon-cache`, `update-desktop-database` | Jun 29 21:25 | Icons not showing |
| 8 | `fc-cache -f` | Jun 30 00:15 | Fontconfig version mismatch |
| 9 | Remove Brave SingletonLock | Jun 30 00:42 | Stale profile lock |
| 10 | AUR installs (qt5-location, qt5-webchannel, qt5-websockets) | Jun 29 00:07 | Dependencies for other apps |
| 11 | `virtualbox-meta` → `virtualbox-host-dkms` | Jun 29 21:06 | Meta package conflict |

### Packages Gone from AUR
- `nocowboy` — removed from AUR (needs local .pkg.tar.zst)
- `ypn-client` — removed from AUR

### Packages Needing Special Handling
- `davinci-resolve` — AUR package needs manual download from Blackmagic Design website
- `happ-desktop-bin` — conflicts with `happ` from official repos
- `nodejs-lts-jod` — preinstalled by Garuda, conflicts with `npm`

---

## Fix Specification

### A. restore.sh — Package Installation Phase

```
Current (BROKEN):
  cat packages.txt | tr '\n' ' ' → one massive pacman -S command
  || true swallows errors
  grep -v warning: hides diagnostics

Fixed (REQUIRED):
  1. Analyze: pacman -Si each package → native vs AUR
  2. Resolve conflicts: remove blocking packages (nodejs-lts-jod, happ)
  3. Install native one-at-a-time via pacman
  4. Install AUR one-at-a-time via paru
  5. Report: installed/skipped/failed counts
  6. No error swallowing, no output filtering
```

### B. restore.sh — Post-Restore Fixes

Must add after all packages installed:
1. `fc-cache -f` — rebuild font cache (fix fontconfig version mismatch)
2. `gtk-update-icon-cache -f -t ~/.icons ~/.local/share/icons` — rebuild icon cache
3. `update-desktop-database ~/.local/share/applications` — rebuild desktop DB
4. Remove stale browser locks: `rm -f ~/.config/BraveSoftware/Brave-Browser/Singleton*`
5. Verify GPG: `sudo pacman-key --populate archlinux garuda` if issues

### C. restore.sh — Conflict Resolution

Pre-install cleanup:
1. `pacman -Rdd --noconfirm nodejs-lts-jod 2>/dev/null || true` — remove Garuda's node if present
2. `pacman -Rdd --noconfirm happ 2>/dev/null || true` — if switching to happ-desktop-bin
3. Handle virtualbox: prefer `virtualbox-host-dkms` over `virtualbox-meta`

### D. backup.sh — Ensure Latest Restore Script

Backup script already copies restore.sh from SCRIPT_DIR. Verify it also copies tools/ directory.

### E. Missing from backup.sh

- Does NOT back up `/etc/pacman.d/gnupg/` — GPG keys can break
- Does NOT back up custom pacman hooks
- The `trap cleanup EXIT` deletes temp dir — OK since tarball captures everything first

---

## Files to Change

| File | Section | Change |
|------|---------|--------|
| `scripts/restore.sh` | Lines 93-189 | ✅ Already fixed (package install one-at-a-time) |
| `scripts/restore.sh` | Lines 23-36 | Add pre-install conflict resolution |
| `scripts/restore.sh` | Lines 960-982 | Enhance post-restore cleanup (add browser lock removal, GPG check) |
| `scripts/backup.sh` | Line 155 | Ensure tools/ directory is copied |
| `scripts/backup.sh` | New | Add GPG trust database backup |
