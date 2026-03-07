# Garuda Linux System Backup & Restore

Complete backup, restore, and system configuration management for Garuda KDE Linux.

**Hardware-Agnostic:** Works on any Garuda Linux system — laptop, desktop, VM — with automatic hardware detection and conditional optimization application.

---

## Quick Start

```bash
# Backup your system
./scripts/backup.sh

# Restore on fresh install
./scripts/restore.sh

# System health check
check           # Quick check (10 areas)
check --deep    # Deep analysis (18 areas)

# System update & maintenance
update
```

---

## What's New: Hardware-Agnostic Restore Kit

The restore kit now **automatically detects your hardware** and applies only the optimizations that are relevant:

| Hardware Feature | Detection | Applied Optimization |
|-----------------|-----------|---------------------|
| **NVIDIA GPU** | lspci | `nvidia_drm.modeset=1`, framebuffer fixes |
| **AMD GPU** | lspci | `amdgpu.sg_display=0` (flicker fix) |
| **Intel GPU** | lspci | `i915.enable_psr=0` (tearing fix) |
| **Hybrid GPU** | Intel + NVIDIA/AMD | DDC/CI disable, power management |
| **Multi-Monitor** | Display detection | KWin DRM fixes, compositor tuning |
| **NVMe SSD** | Block device detection | `kyber` I/O scheduler |
| **ASUS Laptop** | asusctl availability | Power profiles, fan curves |
| **ZRAM** | /dev/zram detection | Swappiness optimization (133) |

**No manual editing required** — the restore kit adapts to your hardware.

---

## Project Structure

```
garuda-restore/
├── README.md                        # This file
├── CLAUDE.md                        # AI assistant instructions
├── docs/
│   ├── HARDWARE-AGNOSTIC-ARCHITECTURE.md  # Architecture design
│   ├── SETTINGS-DOCUMENTATION.md          # Every setting explained
│   ├── SYSTEM-STATE.md                    # Current frozen config
│   ├── QUICK-REFERENCE.md                 # Daily commands
│   ├── CHANGELOG.md                       # Version history
│   └── ...                                # Other documentation
├── scripts/
│   ├── backup.sh                          # Full system backup
│   ├── restore.sh                         # One-click restore
│   └── tools/
│       ├── detect-hardware.sh             # Hardware detection (NEW)
│       ├── apply-optimizations.sh         # Conditional optimizations (NEW)
│       ├── system-health-check.sh         # check command
│       └── system-update.sh               # update command
└── pacman-hooks/
    └── track-installs.hook                # Package tracking
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
| **AI Coding Tools** | Claude Code, Codex, Qwen Code configs |

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
| [COMIC-AI-WORKFLOW.md](docs/COMIC-AI-WORKFLOW.md) | Production workflow for comic consistency (style/characters/animation) |
| [HERO-PROMPTS.md](docs/HERO-PROMPTS.md) | Reusable prompt kit for character sheets, outfits, angles, and consistency |
| [HEROES-TOM1.yaml](docs/HEROES-TOM1.yaml) | Canon character roster and generation order for volume 1 |
| [HERO-PROMPTS-TOM1.md](docs/HERO-PROMPTS-TOM1.md) | Ready prompt stubs for Dima, Mila, Vika, Navigator, Atos, Aramis, Bundla, Klim |
| [GEOGRAF-CHARACTERS-FULL.md](docs/GEOGRAF-CHARACTERS-FULL.md) | Full canon character file (appearance, clothing, traits, age-by-volume, notes) |
| [GEOGRAF-CHARACTER-AGE-MAP.md](docs/GEOGRAF-CHARACTER-AGE-MAP.md) | Full canon character list with ages across volumes |
| [GEOGRAF-CHARACTERS-CANON.yaml](docs/GEOGRAF-CHARACTERS-CANON.yaml) | Machine-readable canon roster with age-by-volume lines |

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

### Duplicate Titlebars (System + App Colored)

Apps showing TWO titlebars (gray KDE one + app's colored one)?

```bash
# Remove system titlebars from Electron/GTK apps
./scripts/force-system-titlebars.sh
```

This removes KDE decorations from apps that already have their own titlebars:
- VSCode, Chrome, Brave, Discord, Slack
- Only the app's colored titlebar remains

For full guide: See `docs/SYSTEM-STATE.md` → "Duplicate Titlebars Fix"

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
