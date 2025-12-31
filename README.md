# Garuda Linux System Backup & Restore

Complete backup, restore, and system configuration management for Garuda KDE Linux.

---

## Quick Start

```bash
# Backup your system
./scripts/backup-settings.sh

# Restore on fresh install
./scripts/restore.sh

# Restore frozen config (after breaking changes)
./scripts/restore-frozen-config.sh

# System health check
check

# System update & maintenance
update
```

---

## Project Structure

```
garuda-restore/
├── README.md                    # This file
├── CLAUDE.md                    # AI assistant instructions
├── configs/
│   └── frozen-2024-12-30/       # Frozen known-good configuration
│       ├── etc-environment      # /etc/environment backup
│       ├── kwinrc               # KWin compositor config
│       ├── kwinoutputconfig.json # Display settings
│       ├── kwinrulesrc          # Window rules
│       └── firefox.conf         # Firefox environment
├── docs/
│   ├── SYSTEM-STATE.md          # Current config & WHY each setting
│   ├── QUICK-REFERENCE.md       # Cheat sheet for daily use
│   ├── CHANGELOG.md             # All changes with rollback commands
│   └── KWIN-HYBRID-GPU.md       # Hybrid GPU troubleshooting
├── packages/
│   ├── explicitly-installed.txt # Pacman packages
│   └── aur-packages.txt         # AUR packages
└── scripts/
    ├── backup-settings.sh       # Full system backup
    ├── restore.sh               # One-click restore wrapper
    ├── restore-settings.sh      # Full restore logic
    ├── restore-frozen-config.sh # Restore frozen config only
    ├── system-health-check.sh   # Interactive health check (check)
    ├── system-update.sh         # Update & maintenance (update)
    ├── daily-backup.sh          # Automated backup with notifications
    ├── setup-daily-backup.sh    # Configure daily backup timer
    ├── daily-drive-sync.sh      # Sync to external backup drive
    ├── setup-drive-sync.sh      # Configure drive sync timer
    ├── setup-zsh.sh             # ZSH shell configuration
    └── setup-zoxide.sh          # Zoxide directory jumper
```

---

## What Gets Backed Up

### Critical Work Data

| Category | Items |
|----------|-------|
| **SSH Keys** | All keys, configs, known_hosts (`~/.ssh/`) |
| **GPG Keys** | Full keyring (`~/.gnupg/`) |
| **Git** | Config, credentials |
| **WiFi** | All saved networks + passwords |
| **VPN** | WireGuard, OpenVPN, Mullvad, Tailscale |
| **Docker** | Config, volumes, compose files |

### Development Environments

| Environment | What's Saved |
|-------------|--------------|
| **Node.js** | NVM, npm, yarn configs |
| **Python** | Conda envs, pyenv, poetry, pipx |
| **Rust** | Cargo, rustup |
| **Go** | GOPATH |
| **Ruby** | Gem, rbenv, rvm |
| **PHP** | Composer |

### Desktop & Apps

| Category | What's Saved |
|----------|--------------|
| **KDE Plasma** | Panels, widgets, shortcuts, themes, effects |
| **Browsers** | Brave, Chrome, Chromium (full profiles) |
| **Apps** | All `~/.config/` settings |
| **Visual** | Wallpapers, fonts, icons, themes |

---

## Scripts

### backup-settings.sh
**Core backup script** - creates complete system backup archive.
```bash
./scripts/backup-settings.sh
# Output: ~/garuda-backup-YYYY-MM-DD.tar.gz
```
Use this for manual backups.

### restore.sh
One-click restore on fresh Garuda install.
```bash
./scripts/restore.sh
```
Finds backup, extracts, restores everything, prompts for reboot.

### restore-frozen-config.sh
Restores only the frozen KWin/display config.
```bash
./scripts/restore-frozen-config.sh
# Then logout/login
```
**Use when:** Display broken, screen flickering, mouse lag after updates.

### system-health-check.sh
**Interactive health check** - analyzes system and offers to fix issues.
```bash
check   # Run from anywhere
```
**Checks:** temps, CPU/GPU, memory, disk, KWin, services, packages, filesystem, errors.

### system-update.sh
**System update & maintenance** - updates, cleans, optimizes.
```bash
update   # Run from anywhere
```
**Does:**
1. Updates system (paru/yay/pacman)
2. Cleans package cache (keeps 2 versions)
3. Removes orphan packages
4. Cleans user cache (thumbnails)
5. Vacuums journal logs
6. Optimizes pacman database, fonts, desktop db

### daily-backup.sh
**Wrapper for automation** - calls `backup-settings.sh` with extras:
- GUI password prompt (ksshaskpass)
- KDE desktop notifications (start/progress/done)
- Auto-deletes backups older than 7 days

Used by systemd timer, not run manually.

### setup-daily-backup.sh
Configure systemd timer for daily backups at midnight.
```bash
./scripts/setup-daily-backup.sh
```

### daily-drive-sync.sh
Rsync working drive to backup drive (incremental).

### setup-drive-sync.sh
Configure systemd timer for drive sync.

---

## Frozen Configuration

The `configs/frozen-2024-12-30/` contains known-good settings after extensive troubleshooting.

### Why Freeze?

Optimized for:
- ASUS TUF Gaming F15 (i7-12700H + RTX 3070)
- Triple 1440p monitors (165Hz/144Hz)
- Wayland + KWin compositor
- Hybrid Intel/NVIDIA GPU

### Critical Settings

| File | Key Settings |
|------|--------------|
| `etc-environment` | `KWIN_DRM_NO_DIRECT_SCANOUT=1` |
| `kwinrc` | Blur disabled, safe effects only |
| `kwinoutputconfig.json` | DDC/CI disabled, VRR disabled |
| `kwinrulesrc` | No global opacity rules |
| `firefox.conf` | `MOZ_USE_XINPUT2=1` |

### Restore Frozen Config

```bash
./scripts/restore-frozen-config.sh
# Logout/login
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [SYSTEM-STATE.md](docs/SYSTEM-STATE.md) | Current config, WHY each setting, DO NOT TOUCH list |
| [QUICK-REFERENCE.md](docs/QUICK-REFERENCE.md) | Daily commands cheat sheet |
| [CHANGELOG.md](docs/CHANGELOG.md) | All changes with rollback commands |
| [KWIN-HYBRID-GPU.md](docs/KWIN-HYBRID-GPU.md) | Hybrid GPU (Intel+NVIDIA) solutions |

---

## Hardware

Tested on:

| Component | Specification |
|-----------|---------------|
| **Laptop** | ASUS TUF Gaming F15 FX507ZR |
| **CPU** | Intel Core i7-12700H (14 cores, 20 threads) |
| **GPU** | NVIDIA RTX 3070 + Intel Iris Xe (hybrid) |
| **RAM** | 32GB DDR5 |
| **Storage** | Dual NVMe SSD (Btrfs + ext4) |
| **Display** | Triple 2560x1440 @ 165Hz/144Hz |

---

## Power Profiles

```bash
# Check current
asusctl profile -p

# Switch profile
asusctl profile -P Balanced     # Daily work (default)
asusctl profile -P Performance  # Gaming, compiling
asusctl profile -P Quiet        # Battery, silent
```

| Profile | Fan Speed | GPU Power |
|---------|-----------|-----------|
| Quiet | Low | Minimal |
| **Balanced** | Medium | On-demand |
| Performance | High | Maximum |

---

## Troubleshooting

### Mouse Lag / High CPU

```bash
asusctl profile -P Balanced
# If still laggy:
./scripts/restore-frozen-config.sh
```

### Screen Flickering

DDC/CI causes NVIDIA I2C errors.
```bash
grep "allowDdcCi" ~/.config/kwinoutputconfig.json
# Should show: "allowDdcCi": false
```

### Internal Display Missing

```bash
cat /etc/environment
# Should NOT have KWIN_DRM_DEVICES line
# If present, remove it and reboot
```

### High Fans at Idle

```bash
nvidia-smi --query-gpu=power.draw,pstate --format=csv
# Should show ~25W, P5 (idle)
# If 60W+, P0: restore frozen config
```

---

## Fresh Install

```bash
# 1. Clone repo
git clone <repo-url> ~/garuda-restore

# 2. Restore
cd ~/garuda-restore
./scripts/restore.sh

# 3. Reboot
sudo reboot
```

---

## After Breaking Update

```bash
./scripts/restore-frozen-config.sh
# Logout/login (or reboot)
```

---

## Requirements

- **OS:** Garuda Linux (or Arch-based)
- **Desktop:** KDE Plasma
- **Packages:** rsync, tar, pacman, paru
- **Optional:** kdialog (for notifications)
