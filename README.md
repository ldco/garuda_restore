# Garuda KDE Linux - ULTIMATE System Backup & Restore

Complete backup and restore scripts for cloning your entire Garuda KDE system.
After restore, your new system will be **identical** to the original.

## ⚠️ WORK-CRITICAL ITEMS (All Backed Up!)

### 🔐 Security & Authentication
| Item | Location | Status |
|------|----------|--------|
| SSH Keys | ~/.ssh (ALL keys, configs, known_hosts) | ✅ |
| GPG Keys | ~/.gnupg (full keyring) | ✅ |
| Git Credentials | ~/.gitconfig, ~/.git-credentials | ✅ |

### 🌐 Networks & VPN
| Item | Location | Status |
|------|----------|--------|
| WiFi Passwords | /etc/NetworkManager/system-connections | ✅ |
| WireGuard | /etc/wireguard/*.conf | ✅ |
| OpenVPN | /etc/openvpn/client/* | ✅ |
| Mullvad VPN | ~/.config/Mullvad VPN | ✅ |
| Tailscale | ~/.config/tailscale | ✅ |

### 🐳 Docker
| Item | Location | Status |
|------|----------|--------|
| Docker Config | ~/.docker | ✅ |
| Docker Volumes | /var/lib/docker/volumes (full tar) | ✅ |
| Compose Files | ~/docker, ~/compose, ~/docker-compose | ✅ |
| Images List | Saved for easy re-pull | ✅ |

### 🐟 Shell & Terminal History
| Item | Location | Status |
|------|----------|--------|
| Fish Config | ~/.config/fish (functions, aliases) | ✅ |
| Fish History | ~/.local/share/fish/fish_history | ✅ |
| Bash History | ~/.bash_history | ✅ |
| Zsh History | ~/.zsh_history | ✅ |
| Starship Prompt | ~/.config/starship.toml | ✅ |

### 💻 Development Environments
| Item | Location | Status |
|------|----------|--------|
| Node.js/NVM | ~/.nvm, ~/.npm, ~/.npmrc | ✅ |
| Yarn | ~/.yarn, ~/.yarnrc | ✅ |
| Python/Conda | ~/.conda, ~/miniconda3/envs | ✅ |
| Python venvs | ~/.local/share/virtualenvs | ✅ |
| Pyenv | ~/.pyenv | ✅ |
| Poetry | ~/.poetry | ✅ |
| Pipx | ~/.local/pipx | ✅ |
| Rust/Cargo | ~/.cargo, ~/.rustup | ✅ |
| Go | ~/go | ✅ |
| PHP/Composer | ~/.composer | ✅ |
| Ruby/Gem | ~/.gem, ~/.rbenv, ~/.rvm | ✅ |

---

## What Else Gets Backed Up

### ✅ KDE/Plasma
- ALL panels, widgets, positions
- Effects (blur, wobbly windows, animations)
- Keyboard shortcuts and layouts
- Themes, colors, window decorations

### ✅ Browsers (Full Profiles)
- Brave, Chrome, Chromium
- History, bookmarks, extensions
- Login sessions (cookies)

### ✅ Applications
- ALL ~/.config (every app's settings)
- Blender, GIMP, Krita, Inkscape plugins
- VS Code extensions

### ✅ Visual
- Wallpapers, Fonts, Icons, Themes
- ICC color profiles

## Daily Automatic Backups

Configured to run at **00:00** (midnight) daily:
- Shows GUI password prompt (ksshaskpass)
- Notifications: Started → In Progress → Complete/Failed
- Auto-cleanup of backups older than 7 days
- Latest backup marked with `-last` suffix

## Files

| File | Purpose |
|------|---------|
| `backup-settings.sh` | Creates complete backup |
| `restore.sh` | **ONE-CLICK restore** (auto-extracts & runs) |
| `restore-settings.sh` | Full restore logic |
| `daily-backup.sh` | Wrapper with notifications |
| `setup-daily-backup.sh` | Configures daily timer |

## Usage

### Manual Backup
```bash
./backup-settings.sh
```

### Restore on Fresh System (ONE COMMAND!)
```bash
./restore.sh
```

That's it! The script will:
1. Find your backup archive automatically
2. Extract it
3. Run the full restore
4. Clean up temp files
5. Prompt you to reboot

## After Restore

Your system will be **identical**:
- Same panels, widgets, wallpaper
- Same keyboard shortcuts and layouts
- Same browser history and logins
- Same app settings and plugins
- Same network/VPN connections
- Daily backup timer auto-configured!

