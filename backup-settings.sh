#!/bin/bash
# ============================================================================
# Garuda KDE Linux - COMPLETE System Settings Backup Script
# ============================================================================
# This script backs up ALL settings from your current Garuda KDE installation
# including: KDE panels, wallpapers, app configs, themes, fonts, and more.
#
# Run this script on your CURRENT system BEFORE reinstalling.
# ============================================================================

set -e

# Use readable date format: 2025-12-12_22-15
READABLE_DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_DIR="$HOME/garuda-backup-$READABLE_DATE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$BACKUP_DIR"/{packages,systemd,system,wallpapers,security,networks,browsers}

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║   Garuda KDE Linux - ULTIMATE COMPLETE System Backup Script          ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""

# ============================================================================
# 1. PACKAGE LISTS
# ============================================================================
echo "[1/14] Backing up package lists..."

pacman -Qe > "$BACKUP_DIR/packages/explicitly-installed.txt"
pacman -Qm > "$BACKUP_DIR/packages/aur-packages.txt"
pacman -Qen > "$BACKUP_DIR/packages/native-packages.txt"
pacman -Qdq > "$BACKUP_DIR/packages/all-deps.txt" 2>/dev/null || true

echo "   ✓ Package lists saved ($(wc -l < "$BACKUP_DIR/packages/explicitly-installed.txt") packages)"

# ============================================================================
# 2. SYSTEMD SERVICES + BACKUP SERVICE ITSELF
# ============================================================================
echo "[2/14] Backing up systemd services (including backup timer)..."

systemctl list-unit-files --state=enabled 2>/dev/null | grep "enabled" | awk '{print $1}' > "$BACKUP_DIR/systemd/system-services.txt"
systemctl --user list-unit-files --state=enabled 2>/dev/null | grep "enabled" | awk '{print $1}' > "$BACKUP_DIR/systemd/user-services.txt"

# Backup the backup service itself!
mkdir -p "$BACKUP_DIR/systemd/user-units"
[ -f "$HOME/.config/systemd/user/garuda-backup.service" ] && cp "$HOME/.config/systemd/user/garuda-backup.service" "$BACKUP_DIR/systemd/user-units/"
[ -f "$HOME/.config/systemd/user/garuda-backup.timer" ] && cp "$HOME/.config/systemd/user/garuda-backup.timer" "$BACKUP_DIR/systemd/user-units/"

# Copy the backup scripts themselves
mkdir -p "$BACKUP_DIR/backup-scripts"
cp "$SCRIPT_DIR"/*.sh "$BACKUP_DIR/backup-scripts/" 2>/dev/null || true

echo "   ✓ Systemd services + backup scripts saved"

# ============================================================================
# 3. ENTIRE ~/.config DIRECTORY (ALL app and KDE settings)
# ============================================================================
echo "[3/14] Backing up ENTIRE ~/.config directory..."
echo "   This includes ALL KDE panels, themes, app settings..."

# Exclude ONLY caches - keep everything else including browser data!
rsync -a --info=progress2 \
    --exclude='*/Cache/' \
    --exclude='*/cache/' \
    --exclude='*/CachedData/' \
    --exclude='*/Code Cache/' \
    --exclude='*/GPUCache/' \
    --exclude='*/Service Worker/CacheStorage/' \
    --exclude='*/ShaderCache/' \
    --exclude='*.log' \
    --exclude='*.log.*' \
    --exclude='crash-reports/' \
    --exclude='Crashpad/' \
    "$HOME/.config/" "$BACKUP_DIR/config/"

echo "   ✓ ~/.config backed up (with browser profiles!)"

# ============================================================================
# 4. ~/.local/share (KDE data, themes, icons, klipper clipboard, etc.)
# ============================================================================
echo "[4/14] Backing up ~/.local/share (KDE data, clipboard, app data)..."

# Create selective backup of important directories
mkdir -p "$BACKUP_DIR/local-share"

LOCAL_SHARE_DIRS=(
    "aurorae"           # Window decorations
    "color-schemes"     # Color schemes
    "konsole"           # Konsole profiles and color schemes
    "kwin"              # KWin scripts
    "plasma"            # Plasma themes and layouts
    "plasma_icons"      # Plasma icons
    "icons"             # User icons
    "applications"      # Desktop files
    "kactivitymanagerd" # Activity manager data
    "kxmlgui5"          # XML GUI configs
    "dolphin"           # Dolphin file manager data
    "kate"              # Kate editor sessions
    "knewstuff3"        # Downloaded KDE addons
    "kpeople"           # Contact data
    "kpeoplevcard"      # Contact vcards
    "krita"             # Krita resources
    "okular"            # Okular settings
    "desktop-directories" # Desktop directories
    "mime"              # MIME associations
    "sddm"              # SDDM themes
    "plasma-systemmonitor" # System monitor layouts
    "gwenview"          # Gwenview settings
    "ark"               # Ark settings
    "showfoto"          # Showfoto settings
    "klipper"           # CLIPBOARD HISTORY!
    "RecentDocuments"   # Recent documents
    "recently-used.xbel" # Recently used files
    "color"             # ICC color profiles
    "icc"               # ICC profiles
    "fonts"             # User fonts
    "blender"           # Blender data
    "fish"              # Fish shell history
    "zsh"               # Zsh history
    "bash-history"      # Bash history
    "networkmanagement" # Network connections
    "telepathy"         # Chat/messaging data
    "TelegramDesktop"   # Telegram data
)

for dir in "${LOCAL_SHARE_DIRS[@]}"; do
    if [ -d "$HOME/.local/share/$dir" ]; then
        cp -r "$HOME/.local/share/$dir" "$BACKUP_DIR/local-share/"
    fi
done

# Important files in .local/share root
for file in "$HOME/.local/share"/*.xbel "$HOME/.local/share"/*rc "$HOME/.local/share"/*.log; do
    [ -f "$file" ] && cp "$file" "$BACKUP_DIR/local-share/" 2>/dev/null || true
done

echo "   ✓ ~/.local/share backed up (with clipboard history!)"

# ============================================================================
# 5. SSH KEYS, GPG KEYS, SECURITY
# ============================================================================
echo "[5/14] Backing up SSH keys, GPG keys, security..."

mkdir -p "$BACKUP_DIR/security"

# SSH keys and config
if [ -d "$HOME/.ssh" ]; then
    cp -r "$HOME/.ssh" "$BACKUP_DIR/security/"
    echo "   ✓ SSH keys backed up"
fi

# GPG keys
if [ -d "$HOME/.gnupg" ]; then
    cp -r "$HOME/.gnupg" "$BACKUP_DIR/security/"
    echo "   ✓ GPG keys backed up"
fi

# Password store (pass)
[ -d "$HOME/.password-store" ] && cp -r "$HOME/.password-store" "$BACKUP_DIR/security/"

echo "   ✓ Security credentials backed up"

# ============================================================================
# 6. WALLPAPERS
# ============================================================================
echo "[6/14] Backing up wallpapers..."

# Find wallpapers referenced in plasma config
WALLPAPER_FILES=$(grep -h "Image=" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null | grep -v "^#" | cut -d'=' -f2 | sort -u)

for wp in $WALLPAPER_FILES; do
    if [ -f "$wp" ]; then
        cp "$wp" "$BACKUP_DIR/wallpapers/"
        echo "   Found: $(basename "$wp")"
    fi
done

# Also backup entire Pictures/Wallpapers folder if it exists
[ -d "$HOME/Pictures/Wallpapers" ] && cp -r "$HOME/Pictures/Wallpapers" "$BACKUP_DIR/wallpapers/"

echo "   ✓ Wallpapers backed up"

# ============================================================================
# 7. FONTS AND ICC PROFILES
# ============================================================================
echo "[7/14] Backing up fonts and ICC color profiles..."

# Fonts
if [ -d "$HOME/.fonts" ]; then
    cp -r "$HOME/.fonts" "$BACKUP_DIR/"
    echo "   ✓ ~/.fonts backed up ($(du -sh "$HOME/.fonts" | cut -f1))"
fi
if [ -d "$HOME/.local/share/fonts" ]; then
    mkdir -p "$BACKUP_DIR/.local-share-fonts"
    cp -r "$HOME/.local/share/fonts/"* "$BACKUP_DIR/.local-share-fonts/" 2>/dev/null || true
    echo "   ✓ ~/.local/share/fonts backed up"
fi

# ICC color profiles
for icc_dir in "$HOME/.local/share/icc" "$HOME/.local/share/color/icc" "$HOME/.color/icc"; do
    if [ -d "$icc_dir" ]; then
        mkdir -p "$BACKUP_DIR/icc-profiles"
        cp -r "$icc_dir/"* "$BACKUP_DIR/icc-profiles/" 2>/dev/null || true
        echo "   ✓ ICC profiles from $icc_dir backed up"
    fi
done

echo "   ✓ Fonts and ICC profiles backed up"

# ============================================================================
# 8. ICONS AND THEMES
# ============================================================================
echo "[8/14] Backing up user icons and themes..."

[ -d "$HOME/.icons" ] && cp -r "$HOME/.icons" "$BACKUP_DIR/"
[ -d "$HOME/.themes" ] && cp -r "$HOME/.themes" "$BACKUP_DIR/"
[ -d "$HOME/.local/share/themes" ] && cp -r "$HOME/.local/share/themes" "$BACKUP_DIR/local-share-themes"

echo "   ✓ Icons and themes backed up"

# ============================================================================
# 9. DOTFILES AND GIT CONFIG
# ============================================================================
echo "[9/14] Backing up dotfiles and git configuration..."

mkdir -p "$BACKUP_DIR/dotfiles"

DOTFILES=(
    ".bashrc"
    ".bash_profile"
    ".bash_history"
    ".profile"
    ".zshrc"
    ".zsh_history"
    ".fish_profile"
    ".gitconfig"
    ".gitignore_global"
    ".git-credentials"
    ".nanorc"
    ".vimrc"
    ".tmux.conf"
    ".inputrc"
    ".Xresources"
    ".xprofile"
    ".xinitrc"
    ".pam_environment"
    ".npmrc"
    ".yarnrc"
    ".cargo/config.toml"
    ".docker/config.json"
)

for dotfile in "${DOTFILES[@]}"; do
    [ -f "$HOME/$dotfile" ] && cp "$HOME/$dotfile" "$BACKUP_DIR/dotfiles/"
done

# Git config directory
[ -d "$HOME/.config/git" ] && cp -r "$HOME/.config/git" "$BACKUP_DIR/dotfiles/"

echo "   ✓ Dotfiles and git config backed up"

# ============================================================================
# 10. NETWORK/VPN CONNECTIONS (requires sudo)
# ============================================================================
echo "[10/14] Backing up network and VPN connections..."

# Refresh sudo credentials (extend timeout)
sudo -v 2>/dev/null || true

# NetworkManager connections (WiFi passwords, VPN configs, etc.)
if sudo test -d "/etc/NetworkManager/system-connections"; then
    sudo cp -r "/etc/NetworkManager/system-connections" "$BACKUP_DIR/networks/"
    sudo chown -R $(id -u):$(id -g) "$BACKUP_DIR/networks/"
    echo "   ✓ NetworkManager connections backed up"
else
    echo "   Note: No NetworkManager connections found"
fi

# WireGuard configs
if sudo test -d "/etc/wireguard"; then
    sudo cp -r "/etc/wireguard" "$BACKUP_DIR/networks/"
    sudo chown -R $(id -u):$(id -g) "$BACKUP_DIR/networks/wireguard" 2>/dev/null
    echo "   ✓ WireGuard configs backed up"
fi

# OpenVPN configs
if sudo test -d "/etc/openvpn/client"; then
    sudo cp -r "/etc/openvpn" "$BACKUP_DIR/networks/"
    sudo chown -R $(id -u):$(id -g) "$BACKUP_DIR/networks/openvpn" 2>/dev/null
    echo "   ✓ OpenVPN configs backed up"
fi

# Tailscale (if exists)
[ -d "$HOME/.config/tailscale" ] && cp -r "$HOME/.config/tailscale" "$BACKUP_DIR/networks/"

# Mullvad VPN settings
[ -d "$HOME/.config/Mullvad VPN" ] && cp -r "$HOME/.config/Mullvad VPN" "$BACKUP_DIR/networks/"

echo "   ✓ Network/VPN connections backed up"

# ============================================================================
# 11. BLENDER PLUGINS AND ADDONS
# ============================================================================
echo "[11/14] Backing up Blender addons and plugins..."

mkdir -p "$BACKUP_DIR/blender"

# Blender config (already in ~/.config, but let's be explicit)
for blender_ver in "$HOME/.config/blender"/*; do
    if [ -d "$blender_ver" ]; then
        cp -r "$blender_ver" "$BACKUP_DIR/blender/"
    fi
done

# Blender scripts/addons from custom locations
[ -d "$HOME/blender-addons" ] && cp -r "$HOME/blender-addons" "$BACKUP_DIR/blender/"
[ -d "$HOME/.blender" ] && cp -r "$HOME/.blender" "$BACKUP_DIR/blender/"

echo "   ✓ Blender addons backed up"

# ============================================================================
# 12. APPLICATION DATA (GIMP, Krita, Inkscape plugins, etc.)
# ============================================================================
echo "[12/14] Backing up application plugins and data..."

mkdir -p "$BACKUP_DIR/app-data"

# GIMP plugins and brushes
[ -d "$HOME/.gimp-2.10" ] && cp -r "$HOME/.gimp-2.10" "$BACKUP_DIR/app-data/"
[ -d "$HOME/.config/GIMP" ] && cp -r "$HOME/.config/GIMP" "$BACKUP_DIR/app-data/"

# Inkscape extensions
[ -d "$HOME/.config/inkscape/extensions" ] && cp -r "$HOME/.config/inkscape/extensions" "$BACKUP_DIR/app-data/inkscape-extensions"

# Krita resources (brushes, patterns, etc.)
[ -d "$HOME/.local/share/krita" ] && cp -r "$HOME/.local/share/krita" "$BACKUP_DIR/app-data/"

# VS Code extensions list
if command -v code &> /dev/null; then
    code --list-extensions > "$BACKUP_DIR/app-data/vscode-extensions.txt" 2>/dev/null || true
fi

echo "   ✓ Application plugins backed up"

# ============================================================================
# 13. DOCKER DATA
# ============================================================================
echo "[13/15] Backing up Docker data..."

mkdir -p "$BACKUP_DIR/docker"

# Docker client config
[ -d "$HOME/.docker" ] && cp -r "$HOME/.docker" "$BACKUP_DIR/docker/"

# Docker compose files from common locations
for compose_dir in "$HOME/docker" "$HOME/compose" "$HOME/docker-compose" "$HOME/.docker-compose"; do
    [ -d "$compose_dir" ] && cp -r "$compose_dir" "$BACKUP_DIR/docker/"
done

# List of images and containers (for reference/recreation)
if command -v docker &> /dev/null && docker info &> /dev/null; then
    docker images --format "{{.Repository}}:{{.Tag}}" > "$BACKUP_DIR/docker/images-list.txt" 2>/dev/null || true
    docker ps -a --format "{{.Names}}: {{.Image}} ({{.Status}})" > "$BACKUP_DIR/docker/containers-list.txt" 2>/dev/null || true
    docker volume ls --format "{{.Name}}" > "$BACKUP_DIR/docker/volumes-list.txt" 2>/dev/null || true
    echo "   ✓ Docker images/containers list saved"

    # Backup docker volumes (requires sudo)
    sudo -v 2>/dev/null || true
    if sudo test -d "/var/lib/docker/volumes"; then
        echo "   Backing up Docker volumes (this may take a while)..."
        sudo tar -czf "$BACKUP_DIR/docker/volumes-backup.tar.gz" -C /var/lib/docker volumes 2>/dev/null || true
        sudo chown $(id -u):$(id -g) "$BACKUP_DIR/docker/volumes-backup.tar.gz" 2>/dev/null || true
        echo "   ✓ Docker volumes backed up"
    fi
else
    echo "   Docker not running, skipping container data"
fi

echo "   ✓ Docker data backed up"

# ============================================================================
# 14. DEVELOPMENT ENVIRONMENTS
# ============================================================================
echo "[14/16] Backing up development environments..."

mkdir -p "$BACKUP_DIR/dev-envs"

# Node.js / NPM / Yarn
[ -d "$HOME/.npm" ] && cp -r "$HOME/.npm" "$BACKUP_DIR/dev-envs/"
[ -f "$HOME/.npmrc" ] && cp "$HOME/.npmrc" "$BACKUP_DIR/dev-envs/"
[ -f "$HOME/.yarnrc" ] && cp "$HOME/.yarnrc" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.yarn" ] && cp -r "$HOME/.yarn" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.nvm" ] && cp -r "$HOME/.nvm" "$BACKUP_DIR/dev-envs/"
echo "   ✓ Node.js/NPM/Yarn settings"

# Python / Conda / Pip
[ -d "$HOME/.conda" ] && cp -r "$HOME/.conda" "$BACKUP_DIR/dev-envs/"
[ -f "$HOME/.condarc" ] && cp "$HOME/.condarc" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.local/share/virtualenvs" ] && cp -r "$HOME/.local/share/virtualenvs" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.pyenv" ] && cp -r "$HOME/.pyenv" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.poetry" ] && cp -r "$HOME/.poetry" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.local/pipx" ] && cp -r "$HOME/.local/pipx" "$BACKUP_DIR/dev-envs/"
[ -f "$HOME/.pip/pip.conf" ] && mkdir -p "$BACKUP_DIR/dev-envs/.pip" && cp "$HOME/.pip/pip.conf" "$BACKUP_DIR/dev-envs/.pip/"
# Miniconda/Anaconda (large, backup config only)
[ -d "$HOME/miniconda3" ] && cp -r "$HOME/miniconda3/envs" "$BACKUP_DIR/dev-envs/conda-envs" 2>/dev/null || true
[ -d "$HOME/anaconda3" ] && cp -r "$HOME/anaconda3/envs" "$BACKUP_DIR/dev-envs/anaconda-envs" 2>/dev/null || true
echo "   ✓ Python/Conda/Pip settings"

# Rust / Cargo
[ -d "$HOME/.cargo" ] && cp -r "$HOME/.cargo" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.rustup" ] && cp -r "$HOME/.rustup" "$BACKUP_DIR/dev-envs/"
echo "   ✓ Rust/Cargo settings"

# Go
[ -d "$HOME/go" ] && cp -r "$HOME/go" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.config/go" ] && cp -r "$HOME/.config/go" "$BACKUP_DIR/dev-envs/"
echo "   ✓ Go settings"

# PHP / Composer
[ -d "$HOME/.composer" ] && cp -r "$HOME/.composer" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.config/composer" ] && cp -r "$HOME/.config/composer" "$BACKUP_DIR/dev-envs/"
echo "   ✓ PHP/Composer settings"

# Ruby / Gem
[ -d "$HOME/.gem" ] && cp -r "$HOME/.gem" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.rbenv" ] && cp -r "$HOME/.rbenv" "$BACKUP_DIR/dev-envs/"
[ -d "$HOME/.rvm" ] && cp -r "$HOME/.rvm" "$BACKUP_DIR/dev-envs/"
echo "   ✓ Ruby/Gem settings"

echo "   ✓ Development environments backed up"

# ============================================================================
# 15. SYSTEM CONFIGS (sudo should already be authenticated)
# ============================================================================
echo "[15/16] Backing up system configurations..."

# Refresh sudo credentials
sudo -v 2>/dev/null || true

# Copy system config files
sudo cp "/etc/samba/smb.conf" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/pacman.conf" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/pacman.d/mirrorlist" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/default/grub" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/hosts" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/fstab" "$BACKUP_DIR/system/fstab.reference" 2>/dev/null || true
sudo cp "/etc/environment" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp -r "/etc/modprobe.d" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp -r "/etc/udev/rules.d" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp -r "/etc/X11/xorg.conf.d" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/vconsole.conf" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/locale.conf" "$BACKUP_DIR/system/" 2>/dev/null || true
sudo cp "/etc/hostname" "$BACKUP_DIR/system/" 2>/dev/null || true

# Docker daemon config
sudo cp "/etc/docker/daemon.json" "$BACKUP_DIR/system/" 2>/dev/null || true

# Fix ownership
sudo chown -R $(id -u):$(id -g) "$BACKUP_DIR/system/" 2>/dev/null || true

echo "   ✓ System configs backed up"

# ============================================================================
# 16. CREATE RESTORE SCRIPT AND ARCHIVE
# ============================================================================
echo "[16/16] Creating backup archive..."

# Copy restore script
cp "$(dirname "$0")/restore-settings.sh" "$BACKUP_DIR/" 2>/dev/null || true

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

# Create compressed archive with readable date
cd "$HOME"
ARCHIVE_NAME="garuda-backup-${READABLE_DATE}.tar.gz"
tar -czf "$ARCHIVE_NAME" "$(basename "$BACKUP_DIR")"

echo "   ✓ Archive created: $HOME/$ARCHIVE_NAME"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║              ULTIMATE COMPLETE BACKUP FINISHED!                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo "Backup archive:   $HOME/$ARCHIVE_NAME"
echo "Total size:       $BACKUP_SIZE"
echo ""
echo "WHAT WAS BACKED UP:"
echo "  ✓ All packages (pacman + AUR)"
echo "  ✓ ALL KDE/Plasma settings (panels, widgets, effects, animations, shortcuts)"
echo "  ✓ ALL application configs (~/.config) with browser profiles & history"
echo "  ✓ SSH keys (~/.ssh)"
echo "  ✓ GPG keys (~/.gnupg)"
echo "  ✓ Network/VPN connections (WiFi passwords, WireGuard, OpenVPN)"
echo "  ✓ Docker (config, volumes, compose files, images list)"
echo "  ✓ DEV ENVS: Node.js/npm/yarn, Python/Conda/pip, Rust/Cargo, Go, PHP, Ruby"
echo "  ✓ Clipboard history (klipper)"
echo "  ✓ Wallpapers"
echo "  ✓ Fonts and ICC color profiles"
echo "  ✓ Icons and themes"
echo "  ✓ Git configuration"
echo "  ✓ Shell configs + history (Fish, Bash, Zsh)"
echo "  ✓ Blender, GIMP, Krita, Inkscape plugins"
echo "  ✓ VS Code extensions list"
echo "  ✓ Systemd services + backup timer"
echo "  ✓ System configs (samba, grub, pacman)"
echo "  ✓ The backup scripts themselves!"
echo ""
echo "NEXT STEPS:"
echo "1. Copy '$ARCHIVE_NAME' to external storage"
echo "2. Install fresh Garuda KDE"
echo "3. Extract and run restore-settings.sh"
echo ""

# Explicitly exit with success
exit 0
