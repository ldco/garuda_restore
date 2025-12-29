# Garuda KDE Linux - ULTIMATE System Backup & Restore

Complete backup and restore scripts for cloning your entire Garuda KDE system.
After restore, your new system will be **identical** to the original.

## Directory Structure

```
garuda-restore/
├── README.md                    # This file
├── docs/
│   ├── SYSTEM-DETECTION.md      # Complete hardware & software inventory
│   └── SYSTEM-ANALYSIS.md       # Deep system analysis, issues & recommendations
├── fixes/
│   ├── README.md                # Fix documentation and rollback instructions
│   ├── apply-fixes.sh           # Interactive fix application script
│   ├── 01-samba-bind-local.conf # Samba security fix
│   ├── 02-blacklist-spd5118.conf # DDR5 sensor driver fix
│   ├── 03-grub-optimizations.conf # Boot optimization
│   └── 04-kwin-hybrid-gpu.md    # GPU framebuffer issue options
├── scripts/
│   ├── backup-settings.sh       # Main backup script
│   ├── restore-settings.sh      # Main restore script
│   ├── restore.sh               # One-click restore wrapper
│   ├── daily-backup.sh          # Automated daily backup with notifications
│   ├── daily-drive-sync.sh      # Rsync to external backup drive
│   ├── setup-daily-backup.sh    # Setup systemd timer for backups
│   └── setup-drive-sync.sh      # Setup systemd timer for drive sync
└── packages/                    # Package lists
```

## Documentation

| Document | Description |
|----------|-------------|
| [SYSTEM-DETECTION.md](docs/SYSTEM-DETECTION.md) | Complete hardware inventory, software versions, system configuration |
| [SYSTEM-ANALYSIS.md](docs/SYSTEM-ANALYSIS.md) | Deep analysis of system health, issues found, and optimization recommendations |
| [fixes/README.md](fixes/README.md) | System fixes with rollback instructions |

## Apply System Fixes

```bash
cd fixes
./apply-fixes.sh
```

Interactive script that applies safe system fixes with confirmation and backup.

---

## WORK-CRITICAL ITEMS (All Backed Up!)

### Security & Authentication
| Item | Location | Status |
|------|----------|--------|
| SSH Keys | ~/.ssh (ALL keys, configs, known_hosts) | Backed up |
| GPG Keys | ~/.gnupg (full keyring) | Backed up |
| Git Credentials | ~/.gitconfig, ~/.git-credentials | Backed up |

### Networks & VPN
| Item | Location | Status |
|------|----------|--------|
| WiFi Passwords | /etc/NetworkManager/system-connections | Backed up |
| WireGuard | /etc/wireguard/*.conf | Backed up |
| OpenVPN | /etc/openvpn/client/* | Backed up |
| Mullvad VPN | ~/.config/Mullvad VPN | Backed up |
| Tailscale | ~/.config/tailscale | Backed up |

### Docker
| Item | Location | Status |
|------|----------|--------|
| Docker Config | ~/.docker | Backed up |
| Docker Volumes | /var/lib/docker/volumes (full tar) | Backed up |
| Compose Files | ~/docker, ~/compose, ~/docker-compose | Backed up |
| Images List | Saved for easy re-pull | Backed up |

### Shell & Terminal History
| Item | Location | Status |
|------|----------|--------|
| Fish Config | ~/.config/fish (functions, aliases) | Backed up |
| Fish History | ~/.local/share/fish/fish_history | Backed up |
| Bash History | ~/.bash_history | Backed up |
| Zsh History | ~/.zsh_history | Backed up |
| Starship Prompt | ~/.config/starship.toml | Backed up |

### Development Environments
| Item | Location | Status |
|------|----------|--------|
| Node.js/NVM | ~/.nvm, ~/.npm, ~/.npmrc | Backed up |
| Yarn | ~/.yarn, ~/.yarnrc | Backed up |
| Python/Conda | ~/.conda, ~/miniconda3/envs | Backed up |
| Python venvs | ~/.local/share/virtualenvs | Backed up |
| Pyenv | ~/.pyenv | Backed up |
| Poetry | ~/.poetry | Backed up |
| Pipx | ~/.local/pipx | Backed up |
| Rust/Cargo | ~/.cargo, ~/.rustup | Backed up |
| Go | ~/go | Backed up |
| PHP/Composer | ~/.composer | Backed up |
| Ruby/Gem | ~/.gem, ~/.rbenv, ~/.rvm | Backed up |

---

## What Else Gets Backed Up

### KDE/Plasma
- ALL panels, widgets, positions
- Effects (blur, wobbly windows, animations)
- Keyboard shortcuts and layouts
- Themes, colors, window decorations

### Browsers (Full Profiles)
- Brave, Chrome, Chromium
- History, bookmarks, extensions
- Login sessions (cookies)

### Applications
- ALL ~/.config (every app's settings)
- Blender, GIMP, Krita, Inkscape plugins
- VS Code extensions

### Visual
- Wallpapers, Fonts, Icons, Themes
- ICC color profiles

---

## Daily Automatic Backups

Configured to run at **00:00** (midnight) daily:
- Shows GUI password prompt (ksshaskpass)
- Notifications: Started -> In Progress -> Complete/Failed
- Auto-cleanup of backups older than 7 days
- Latest backup marked with `-last` suffix

---

## Scripts

| File | Purpose |
|------|---------|
| `scripts/backup-settings.sh` | Creates complete backup |
| `scripts/restore.sh` | **ONE-CLICK restore** (auto-extracts & runs) |
| `scripts/restore-settings.sh` | Full restore logic |
| `scripts/daily-backup.sh` | Wrapper with notifications |
| `scripts/daily-drive-sync.sh` | Rsync working drive to backup drive |
| `scripts/setup-daily-backup.sh` | Configures daily backup timer |
| `scripts/setup-drive-sync.sh` | Configures drive sync timer |

---

## Usage

### Manual Backup
```bash
cd scripts
./backup-settings.sh
```

### Setup Automated Daily Backups
```bash
cd scripts
./setup-daily-backup.sh
```

### Restore on Fresh System (ONE COMMAND!)
```bash
cd scripts
./restore.sh
```

That's it! The script will:
1. Find your backup archive automatically
2. Extract it
3. Run the full restore
4. Clean up temp files
5. Prompt you to reboot

---

## After Restore

Your system will be **identical**:
- Same panels, widgets, wallpaper
- Same keyboard shortcuts and layouts
- Same browser history and logins
- Same app settings and plugins
- Same network/VPN connections
- Daily backup timer auto-configured!

---

## System Requirements

- Garuda Linux (or Arch-based distro)
- KDE Plasma desktop
- rsync, tar, pacman
- paru (for AUR packages)
- Optional: kdialog (for GUI notifications)
# test
