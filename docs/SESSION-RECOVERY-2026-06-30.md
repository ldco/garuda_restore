# Session Recovery — June 30, 2026

## Backup Archive
- **File**: `garuda-backup-2026-06-30_01-41.tar.gz` (6.6GB)
- **Location**: `/run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb/LinuxDCO/backups/`
- **Backup drive UUID**: `3734114f-7123-41f5-8f63-7f43c94879eb` (added to fstab for auto-mount)

---

## 9 Commits — All Fixes Applied

```
1cf4d2a feat(restore): VPN-first — install Happ + restore keys BEFORE system update
a410310 fix(restore): wallpaper for all 3 surfaces — desktop + lock + SDDM login
3b13e76 fix(restore): pip packages via pacman/pipx instead of --break-system-packages
5584892 fix(restore): npm scoped package parsing + pip PEP 668 compat
a31710a fix(backup): robust wallpaper sources + resilient SSH/GPG copy
9bf961a fix: wallpaper auto-apply, user avatar backup, AUR exclude list
4feb8fe fix(backup): temp dir management, sudo handling, tools/ backup
c3c7bbe fix(restore): add pre-flight conflict resolution and post-restore cleanup
b3ae093 fix(restore): install packages one-at-a-time, separate native vs AUR
```

---

## Root Cause of Previous Restore Failure

`restore.sh` step 4 concatenated all 382 packages into ONE `pacman -S` command via `tr '\n' ' '`. AUR-only packages (davinci-resolve, happ-desktop-bin, nocowboy, ypn-client) in the explicit list caused pacman to fail. `|| true` silently swallowed the error. **84 of 382 packages never installed.**

## Restore Script Flow (After Fixes)

```
Step 0: Pre-flight (remove conflicting packages, refresh GPG)
Step 1: VPN FIRST
  1a: Install paru + chaotic-AUR
  1b: Install happ-desktop-bin (AUR) or happ (repo fallback)
  1c: Restore Happ.conf + subs.db from backup → VPN keys active
  1d: Start happd daemon → VPN tunnel UP
Step 2: pacman -Syu (through secure VPN)
Step 3: Hardware detection
Step 4-5: Chaotic-AUR + paru (verify)
Step 6+: Install 395+ packages one-at-a-time, separate native vs AUR
```

## Package Installation (Key Fixes)

- **pacman**: One-at-a-time, separate native vs AUR via `pacman -Si` check
- **npm**: Fixed scoped package parsing (`@scope/name@version` with `sed 's/@[^@]*$//'`)
- **pip**: Installs via pacman (`python-<name>`) or pipx instead of `--break-system-packages`
- **AUR**: Excludes unavailable packages (nocowboy, ypn-client) via install-tracker filter
- **davinci-resolve**: Manual download required (Blackmagic website EULA) — script warns

## Post-Restore Fixes (All Automated)

1. **Font cache**: `fc-cache -f` (fixes version mismatch)
2. **Icon cache**: `gtk-update-icon-cache`
3. **Desktop database**: `update-desktop-database`
4. **Browser locks**: Remove stale `SingletonLock/Cookie/Socket` (Brave, Chrome, Chromium)
5. **GPG keyring**: Verify + repair if needed (`pacman-key --populate`)
6. **Wallpaper**: 
   - Desktop: KDE autostart script (runs `plasma-apply-wallpaperimage` on first login, self-deletes)
   - Lock screen: `kwriteconfig6` to `kscreenlockerrc`
   - SDDM login: Copy to `/usr/share/sddm/themes/Dr460nized/background.png`
7. **User avatar**: Backup/restore `~/.face.icon` (via security section)

---

## Manual Fixes Applied to Current System

1. **84 missing packages**: Installed one-at-a-time via pacman (80 native + 4 AUR via paru)
2. **npm globals**: `@kilocode/cli`, `@mimo-ai/cli`, `cline`, `codewhale`, `mcp-proxy`, `tsx`, `@qwen-code/qwen-code` installed
3. **pip packages**: `python-bcrypt`, `python-invoke`, `python-paramiko` via pacman
4. **/etc/environment**: Restored `KWIN_DRM_NO_DIRECT_SCANOUT=1` (fixes multi-monitor NVIDIA sleep/wake)
5. **Drive auto-mount**: Added UUID `3734114f-7123-41f5-8f63-7f43c94879eb` to `/etc/fstab`
6. **Brave stale lock**: Removed `SingletonLock/Cookie/Socket`
7. **Fontconfig cache**: Rebuilt with `fc-cache -f`
8. **KDE icons/themes**: Restored from backup's `local-share/{icons,plasma,plasma_icons,aurorae,color-schemes}`
9. **Wallpaper**: Set for all 3 screens (desktop + lock + SDDM login)
10. **Overview/Meta key**: Fixed conflict — removed Meta from Application Launcher, kept for Overview
11. **KDE panels**: Restored backup plasma config (kwriteconfig6 `\x5b` bracket escaping had corrupted it)
12. **NVIDIA GSP firmware**: Confirmed active (610.43.02) — VRAM preserved during suspend

---

## Known Remaining Issues

| Issue | Status | Resolution |
|-------|--------|------------|
| **davinci-resolve** | Not installed | AUR package needs manual download from Blackmagic website |
| **happ-desktop-bin** | `happ` (repo) installed instead | Both work, VPN keys restored from backup |
| **nocowboy, ypn-client** | Removed from AUR | Excluded from future backups |
| **npm permissions** | Needs `sudo npm install -g` | Script handles via sudo |
| **Brave sync seed** | Decrypt failure | Expected — OS keyring changed after reinstall. Re-auth in Brave. |
| **zoxide database** | Empty | Was empty on old system — needs manual `zoxide add` |
| **git config** | Default values | Was default on old system — needs `git config --global user.name/email` |
| **OWASP compliance** | Not verified | e2guardian requires manual attention (network filtering) |
| **Plasma config** | Restored from backup | Containment IDs differ — panels work, wallpaper via autostart |

---

## Fresh Restore Procedure

```bash
# 1. Install fresh Garuda KDE
# 2. Copy backup archive to new system
# 3. Extract and run restore:
tar -xzf garuda-backup-2026-06-30_01-41.tar.gz
cd .tmp-garuda-backup-2026-06-30_01-41/
bash restore.sh

# 4. The script will:
#    - Install Happ + VPN keys FIRST
#    - Start VPN tunnel
#    - Update system through VPN
#    - Install all 395+ packages one-at-a-time
#    - Restore all configs, wallpapers, fonts, icons
#    - Reboot

# 5. After reboot:
#    - Wallpaper auto-applies on first login
#    - If panels don't appear: kquitapp6 plasmashell && kstart6 plasmashell
#    - Set user avatar in System Settings → Users
#    - Re-auth Brave sync
#    - Install davinci-resolve manually if needed
```

## Important Config Paths

| Config | Path |
|--------|------|
| Happ VPN keys | `~/.config/Happ.conf` + `~/.config/Happ/subs.db` |
| KDE plasma layout | `~/.config/plasma-org.kde.plasma.desktop-appletsrc` |
| Wallpaper file | `~/Pictures/Gemini_Generated_Image_.png` |
| KWin effects | `~/.config/kwinrc` |
| Global shortcuts | `~/.config/kglobalshortcutsrc` |
| Power management | `~/.config/powerdevilrc` |
| Environment variables | `~/.config/environment.d/*.conf` + `/etc/environment` |
| Drive mount | `/etc/fstab` |
| Backup timer | `~/.config/systemd/user/garuda-backup.timer` |

## Script Locations

| Script | Purpose |
|--------|---------|
| `scripts/backup.sh` | Full system backup (18 steps) |
| `scripts/restore.sh` | Full system restore (23 steps, VPN-first) |
| `scripts/install-tracker.sh` | Captures installed packages (AUR exclude list) |
| `scripts/tools/detect-hardware.sh` | Hardware detection for optimizations |
| `scripts/tools/apply-optimizations.sh` | Apply hardware-specific optimizations |
