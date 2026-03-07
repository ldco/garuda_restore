#!/bin/bash
# ============================================================================
# Garuda KDE Linux - COMPLETE System Settings Backup Script
# ============================================================================
# This script backs up ALL settings from your current Garuda KDE installation.
#
# Usage:
#   ./backup.sh              # Manual backup (interactive)
#   ./backup.sh --daemon     # Scheduled backup (notifications, GUI sudo, archive mgmt)
# ============================================================================

set -e

# ============================================================================
# CONFIGURATION
# ============================================================================
BACKUP_DEST="${BACKUP_DEST:-/run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb/LinuxDCO/backups}"
LOG_FILE="$HOME/.local/share/garuda-backup/backup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_MODE=false

# Parse arguments
[[ "$1" == "--daemon" ]] && DAEMON_MODE=true

# Use readable date format
READABLE_DATE=$(date +%Y-%m-%d_%H-%M)
BACKUP_DIR="$HOME/garuda-backup-$READABLE_DATE"

# ============================================================================
# DAEMON MODE FUNCTIONS (notifications, logging, GUI sudo)
# ============================================================================
if [ "$DAEMON_MODE" = true ]; then
    export DISPLAY="${DISPLAY:-:0}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$BACKUP_DEST"

    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

    notify() {
        local title="$1" message="$2" icon="$3" urgency="${4:-normal}"
        command -v notify-send &>/dev/null && notify-send -u "$urgency" -i "$icon" -a "Garuda Backup" "$title" "$message" 2>/dev/null
    }

    log "=========================================="
    log "Starting scheduled backup"
    notify "🔄 Garuda Backup Started" "Preparing backup...\nYou will be asked for your password." "system-run" "normal"

    # GUI sudo authentication
    ASKPASS_SCRIPT=$(mktemp)
    cat > "$ASKPASS_SCRIPT" << 'ASKPASS_EOF'
#!/bin/bash
if command -v kdialog &>/dev/null; then
    kdialog --password "Garuda Backup requires administrator privileges.\n\nEnter your password:" --title "🔐 Garuda Backup"
elif command -v zenity &>/dev/null; then
    zenity --password --title="Garuda Backup"
else
    /usr/bin/ksshaskpass "Garuda Backup - Enter password:"
fi
ASKPASS_EOF
    chmod +x "$ASKPASS_SCRIPT"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"

    if ! sudo -A -v 2>/dev/null && ! sudo -v 2>/dev/null; then
        log "ERROR: Sudo authentication failed"
        notify "❌ Garuda Backup Cancelled" "Authentication failed." "dialog-error" "critical"
        rm -f "$ASKPASS_SCRIPT"
        exit 1
    fi
    rm -f "$ASKPASS_SCRIPT"
    log "Sudo authenticated"

    # Keep sudo alive
    (while true; do sleep 60; sudo -n -v 2>/dev/null || break; done) &
    SUDO_PID=$!
    trap "kill $SUDO_PID 2>/dev/null" EXIT

    notify "⏳ Garuda Backup In Progress" "Backing up packages, configs, KDE settings...\nThis may take several minutes." "document-save" "normal"
else
    log() { echo "$1"; }
    notify() { :; }
fi

mkdir -p "$BACKUP_DIR"/{packages,systemd,system,wallpapers,security,networks,browsers}

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║   Garuda KDE Linux - System Backup                                   ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""

# ============================================================================
# 1. INSTALLED SOFTWARE TRACKER (all package managers)
# ============================================================================
echo "[1/18] Running install tracker (pacman, npm, pip, git, flatpak...)..."

# Run the comprehensive install tracker
TRACKER_SCRIPT="$SCRIPT_DIR/install-tracker.sh"
if [ -f "$TRACKER_SCRIPT" ]; then
    bash "$TRACKER_SCRIPT"
fi

# Copy tracker output to backup
TRACKER_DIR="$HOME/.local/share/garuda-backup/installed"
if [ -d "$TRACKER_DIR" ]; then
    cp -r "$TRACKER_DIR" "$BACKUP_DIR/installed-software"
    echo "   ✓ Install tracker data copied"
fi

# Also keep the legacy package lists for compatibility
pacman -Qe > "$BACKUP_DIR/packages/explicitly-installed.txt"
pacman -Qm > "$BACKUP_DIR/packages/aur-packages.txt"
pacman -Qen > "$BACKUP_DIR/packages/native-packages.txt"
pacman -Qdq > "$BACKUP_DIR/packages/all-deps.txt" 2>/dev/null || true

echo "   ✓ Package lists saved ($(wc -l < "$BACKUP_DIR/packages/explicitly-installed.txt") packages)"

# ============================================================================
# 2. SYSTEMD SERVICES + BACKUP SERVICE ITSELF
# ============================================================================
echo "[2/18] Backing up systemd services (including backup timer)..."

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
echo "[3/18] Backing up ENTIRE ~/.config directory..."
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
echo "[4/18] Backing up ~/.local/share (KDE data, clipboard, app data)..."

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
        cp -r "$HOME/.local/share/$dir" "$BACKUP_DIR/local-share/" 2>/dev/null || true
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
echo "[5/18] Backing up SSH keys, GPG keys, security..."

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
echo "[6/18] Backing up wallpapers..."

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
echo "[7/18] Backing up fonts and ICC color profiles..."

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
echo "[8/18] Backing up user icons and themes..."

[ -d "$HOME/.icons" ] && cp -r "$HOME/.icons" "$BACKUP_DIR/"
[ -d "$HOME/.themes" ] && cp -r "$HOME/.themes" "$BACKUP_DIR/"
[ -d "$HOME/.local/share/themes" ] && cp -r "$HOME/.local/share/themes" "$BACKUP_DIR/local-share-themes"

echo "   ✓ Icons and themes backed up"

# ============================================================================
# 9. DOTFILES AND GIT CONFIG
# ============================================================================
echo "[9/18] Backing up dotfiles and git configuration..."

mkdir -p "$BACKUP_DIR/dotfiles"

DOTFILES=(
    ".bashrc"
    ".bash_profile"
    ".bash_history"
    ".profile"
    ".zshrc"
    ".zsh_history"
    ".p10k.zsh"
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

# Oh My Zsh (plugins, custom themes, custom scripts)
if [ -d "$HOME/.oh-my-zsh/custom" ]; then
    mkdir -p "$BACKUP_DIR/dotfiles/oh-my-zsh-custom"
    cp -r "$HOME/.oh-my-zsh/custom/"* "$BACKUP_DIR/dotfiles/oh-my-zsh-custom/" 2>/dev/null || true
    echo "   ✓ Oh My Zsh custom plugins/themes backed up"
fi

echo "   ✓ Dotfiles and git config backed up"

# ============================================================================
# 10. NETWORK/VPN CONNECTIONS (requires sudo)
# ============================================================================
echo "[10/18] Backing up network and VPN connections..."

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
echo "[11/18] Backing up Blender addons and plugins..."

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
echo "[12/18] Backing up application plugins and data..."

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
echo "[13/18] Backing up Docker data..."

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
# 14. DEVELOPMENT ENVIRONMENTS (CONFIG FILES ONLY - caches are reinstallable)
# ============================================================================
echo "[14/18] Backing up development environment configs..."

mkdir -p "$BACKUP_DIR/dev-envs"

# Track which dev tools are installed (for restore script to reinstall)
DEV_TOOLS_FILE="$BACKUP_DIR/dev-envs/installed-tools.txt"
> "$DEV_TOOLS_FILE"

# Node.js / NPM / Yarn - CONFIG + GLOBAL PACKAGES LIST
[ -f "$HOME/.npmrc" ] && cp "$HOME/.npmrc" "$BACKUP_DIR/dev-envs/" && echo "nodejs" >> "$DEV_TOOLS_FILE"
[ -f "$HOME/.yarnrc" ] && cp "$HOME/.yarnrc" "$BACKUP_DIR/dev-envs/"
[ -f "$HOME/.yarnrc.yml" ] && cp "$HOME/.yarnrc.yml" "$BACKUP_DIR/dev-envs/"
# Save current Node version for reinstall
command -v node &>/dev/null && node -v > "$BACKUP_DIR/dev-envs/node-version.txt"
# Save global npm packages list (for reinstall)
if command -v npm &>/dev/null; then
    npm list -g --depth=0 --json > "$BACKUP_DIR/dev-envs/npm-global-packages.json" 2>/dev/null || true
    npm list -g --depth=0 | tail -n +2 | awk '{print $2}' | cut -d'@' -f1 > "$BACKUP_DIR/dev-envs/npm-global-packages.txt" 2>/dev/null || true
fi
echo "   ✓ Node.js/NPM/Yarn configs + global packages list"

# Python / Conda / Pip - CONFIG ONLY (not envs or caches)
[ -f "$HOME/.condarc" ] && cp "$HOME/.condarc" "$BACKUP_DIR/dev-envs/" && echo "conda" >> "$DEV_TOOLS_FILE"
[ -f "$HOME/.pip/pip.conf" ] && mkdir -p "$BACKUP_DIR/dev-envs/.pip" && cp "$HOME/.pip/pip.conf" "$BACKUP_DIR/dev-envs/.pip/"
[ -f "$HOME/.config/pip/pip.conf" ] && mkdir -p "$BACKUP_DIR/dev-envs/.config/pip" && cp "$HOME/.config/pip/pip.conf" "$BACKUP_DIR/dev-envs/.config/pip/"
# Export conda environment specs (can recreate from these)
if command -v conda &>/dev/null; then
    conda env list --json > "$BACKUP_DIR/dev-envs/conda-envs.json" 2>/dev/null || true
    for env in $(conda env list | grep -v "^#" | awk '{print $1}' | grep -v "^$"); do
        conda env export -n "$env" > "$BACKUP_DIR/dev-envs/conda-env-$env.yml" 2>/dev/null || true
    done
fi
command -v python &>/dev/null && python --version > "$BACKUP_DIR/dev-envs/python-version.txt" 2>&1
echo "   ✓ Python/Conda/Pip configs"

# Rust / Cargo - CONFIG ONLY (not registry cache or toolchains)
[ -f "$HOME/.cargo/config.toml" ] && mkdir -p "$BACKUP_DIR/dev-envs/.cargo" && cp "$HOME/.cargo/config.toml" "$BACKUP_DIR/dev-envs/.cargo/" && echo "rust" >> "$DEV_TOOLS_FILE"
[ -f "$HOME/.cargo/config" ] && mkdir -p "$BACKUP_DIR/dev-envs/.cargo" && cp "$HOME/.cargo/config" "$BACKUP_DIR/dev-envs/.cargo/"
# Save installed Rust version
command -v rustc &>/dev/null && rustc --version > "$BACKUP_DIR/dev-envs/rust-version.txt"
echo "   ✓ Rust/Cargo configs"

# Go - CONFIG ONLY (not pkg/mod cache)
[ -f "$HOME/go/env" ] && mkdir -p "$BACKUP_DIR/dev-envs/go" && cp "$HOME/go/env" "$BACKUP_DIR/dev-envs/go/" && echo "go" >> "$DEV_TOOLS_FILE"
[ -d "$HOME/.config/go" ] && cp -r "$HOME/.config/go" "$BACKUP_DIR/dev-envs/"
# Save Go version
command -v go &>/dev/null && go version > "$BACKUP_DIR/dev-envs/go-version.txt"
echo "   ✓ Go configs"

# PHP / Composer - CONFIG ONLY
[ -f "$HOME/.composer/config.json" ] && mkdir -p "$BACKUP_DIR/dev-envs/.composer" && cp "$HOME/.composer/config.json" "$BACKUP_DIR/dev-envs/.composer/" && echo "php" >> "$DEV_TOOLS_FILE"
[ -f "$HOME/.composer/auth.json" ] && cp "$HOME/.composer/auth.json" "$BACKUP_DIR/dev-envs/.composer/"
[ -f "$HOME/.config/composer/config.json" ] && mkdir -p "$BACKUP_DIR/dev-envs/.config/composer" && cp "$HOME/.config/composer/config.json" "$BACKUP_DIR/dev-envs/.config/composer/"
echo "   ✓ PHP/Composer configs"

# Ruby / Gem - CONFIG ONLY
[ -f "$HOME/.gemrc" ] && cp "$HOME/.gemrc" "$BACKUP_DIR/dev-envs/" && echo "ruby" >> "$DEV_TOOLS_FILE"
command -v ruby &>/dev/null && ruby --version > "$BACKUP_DIR/dev-envs/ruby-version.txt"
echo "   ✓ Ruby/Gem configs"

# Remove duplicates from installed tools list
sort -u "$DEV_TOOLS_FILE" -o "$DEV_TOOLS_FILE"

echo "   ✓ Development configs backed up (caches excluded - will reinstall on restore)"

# ============================================================================
# 15. SYSTEM CONFIGS (sudo should already be authenticated)
# ============================================================================
echo "[15/18] Backing up system configurations..."

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
# 16. AI TOOLS (ComfyUI, Fooocus, Claude Code, Codex, Qwen Code) - CONFIG ONLY, NOT MODELS
# ============================================================================
echo "[16/18] Backing up AI tools configuration (ComfyUI, Fooocus, Claude Code, Codex, Qwen Code)..."

mkdir -p "$BACKUP_DIR/ai-tools"

# Claude Code - global config, commands, templates, settings
if [ -d "$HOME/.claude" ] || [ -f "$HOME/.claude.json" ]; then
    mkdir -p "$BACKUP_DIR/ai-tools/claude-code"

    # Main config file
    [ -f "$HOME/.claude.json" ] && cp "$HOME/.claude.json" "$BACKUP_DIR/ai-tools/claude-code/"

    # Settings and credentials (but NOT cache/debug/telemetry)
    [ -f "$HOME/.claude/settings.json" ] && cp "$HOME/.claude/settings.json" "$BACKUP_DIR/ai-tools/claude-code/"
    [ -f "$HOME/.claude/.credentials.json" ] && cp "$HOME/.claude/.credentials.json" "$BACKUP_DIR/ai-tools/claude-code/"

    # Custom commands, templates, roles, scripts
    [ -d "$HOME/.claude/commands" ] && cp -r "$HOME/.claude/commands" "$BACKUP_DIR/ai-tools/claude-code/"
    [ -d "$HOME/.claude/templates" ] && cp -r "$HOME/.claude/templates" "$BACKUP_DIR/ai-tools/claude-code/"
    [ -d "$HOME/.claude/roles" ] && cp -r "$HOME/.claude/roles" "$BACKUP_DIR/ai-tools/claude-code/"
    [ -d "$HOME/.claude/scripts" ] && cp -r "$HOME/.claude/scripts" "$BACKUP_DIR/ai-tools/claude-code/"
    [ -d "$HOME/.claude/knowledge" ] && cp -r "$HOME/.claude/knowledge" "$BACKUP_DIR/ai-tools/claude-code/"

    echo "   ✓ Claude Code config backed up"
fi

# Codex CLI / Codex config
if [ -d "$HOME/.codex" ]; then
    mkdir -p "$BACKUP_DIR/ai-tools/codex"
    rsync -a "$HOME/.codex/" "$BACKUP_DIR/ai-tools/codex/" 2>/dev/null || true
    echo "   ✓ Codex config backed up"
fi

# Qwen Code config (supports common locations)
if [ -d "$HOME/.qwen-code" ] || [ -d "$HOME/.qwen" ] || [ -d "$HOME/.config/qwen-code" ] || [ -f "$HOME/.qwen-code.json" ]; then
    mkdir -p "$BACKUP_DIR/ai-tools/qwen-code"

    [ -f "$HOME/.qwen-code.json" ] && cp "$HOME/.qwen-code.json" "$BACKUP_DIR/ai-tools/qwen-code/"
    [ -d "$HOME/.qwen-code" ] && rsync -a "$HOME/.qwen-code/" "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen-code/" 2>/dev/null || true
    [ -d "$HOME/.qwen" ] && rsync -a "$HOME/.qwen/" "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen/" 2>/dev/null || true
    [ -d "$HOME/.config/qwen-code" ] && rsync -a "$HOME/.config/qwen-code/" "$BACKUP_DIR/ai-tools/qwen-code/config-qwen-code/" 2>/dev/null || true

    echo "   ✓ Qwen Code config backed up"
fi

# ComfyUI - backup config, custom nodes list, workflows (NOT models ~70GB)
if [ -d "$HOME/ComfyUI" ]; then
    mkdir -p "$BACKUP_DIR/ai-tools/comfyui"

    # Save list of installed custom nodes (git repos to re-clone)
    if [ -d "$HOME/ComfyUI/custom_nodes" ]; then
        echo "# ComfyUI Custom Nodes - git clone these on restore" > "$BACKUP_DIR/ai-tools/comfyui/custom-nodes.txt"
        for node_dir in "$HOME/ComfyUI/custom_nodes"/*/; do
            if [ -d "$node_dir/.git" ]; then
                NODE_NAME=$(basename "$node_dir")
                NODE_URL=$(git -C "$node_dir" remote get-url origin 2>/dev/null || echo "unknown")
                echo "$NODE_NAME|$NODE_URL" >> "$BACKUP_DIR/ai-tools/comfyui/custom-nodes.txt"
            fi
        done
        echo "   ✓ Custom nodes list saved"
    fi

    # Backup workflows (input folder often has workflows)
    [ -d "$HOME/ComfyUI/input" ] && cp -r "$HOME/ComfyUI/input" "$BACKUP_DIR/ai-tools/comfyui/"
    [ -d "$HOME/ComfyUI/user" ] && cp -r "$HOME/ComfyUI/user" "$BACKUP_DIR/ai-tools/comfyui/"

    # Backup our MODELS.md documentation
    [ -f "$HOME/ComfyUI/MODELS.md" ] && cp "$HOME/ComfyUI/MODELS.md" "$BACKUP_DIR/ai-tools/comfyui/"

    # Backup extra_model_paths.yaml if customized
    [ -f "$HOME/ComfyUI/extra_model_paths.yaml" ] && cp "$HOME/ComfyUI/extra_model_paths.yaml" "$BACKUP_DIR/ai-tools/comfyui/"

    # Save Python version used
    [ -f "$HOME/ComfyUI/venv/bin/python" ] && "$HOME/ComfyUI/venv/bin/python" --version > "$BACKUP_DIR/ai-tools/comfyui/python-version.txt" 2>&1

    echo "   ✓ ComfyUI config backed up (models excluded)"
fi

# Fooocus - backup config, presets (NOT models)
if [ -d "$HOME/Fooocus" ]; then
    mkdir -p "$BACKUP_DIR/ai-tools/fooocus"

    # Config files
    [ -f "$HOME/Fooocus/config.txt" ] && cp "$HOME/Fooocus/config.txt" "$BACKUP_DIR/ai-tools/fooocus/"
    [ -f "$HOME/Fooocus/auth.json" ] && cp "$HOME/Fooocus/auth.json" "$BACKUP_DIR/ai-tools/fooocus/"

    # Custom presets and styles
    [ -d "$HOME/Fooocus/presets" ] && cp -r "$HOME/Fooocus/presets" "$BACKUP_DIR/ai-tools/fooocus/"
    [ -f "$HOME/Fooocus/sorted_styles.json" ] && cp "$HOME/Fooocus/sorted_styles.json" "$BACKUP_DIR/ai-tools/fooocus/"

    # Save Python version used
    [ -f "$HOME/Fooocus/venv/bin/python" ] && "$HOME/Fooocus/venv/bin/python" --version > "$BACKUP_DIR/ai-tools/fooocus/python-version.txt" 2>&1

    echo "   ✓ Fooocus config backed up (models excluded)"
fi

# Backup AI tools desktop launchers
mkdir -p "$BACKUP_DIR/ai-tools/launchers"
[ -f "$HOME/.local/share/applications/comfyui.desktop" ] && cp "$HOME/.local/share/applications/comfyui.desktop" "$BACKUP_DIR/ai-tools/launchers/"
[ -f "$HOME/.local/share/applications/fooocus.desktop" ] && cp "$HOME/.local/share/applications/fooocus.desktop" "$BACKUP_DIR/ai-tools/launchers/"

echo "   ✓ AI tools configuration backed up"

# ============================================================================
# 17. BROWSERS (Firefox, Chrome, Brave, etc.) - EXPLICIT BACKUP
# ============================================================================
echo "[17/18] Backing up browser profiles (bookmarks, history, extensions)..."

mkdir -p "$BACKUP_DIR/browsers"

# Firefox / LibreWolf (stored in ~/.mozilla, not ~/.config)
if [ -d "$HOME/.mozilla" ]; then
    rsync -a --info=progress2 \
        --exclude='*/cache2/' \
        --exclude='*/Cache/' \
        --exclude='*/crashes/' \
        --exclude='*.sqlite-shm' \
        --exclude='*.sqlite-wal' \
        "$HOME/.mozilla/" "$BACKUP_DIR/browsers/mozilla/"
    echo "   ✓ Firefox/Mozilla backed up"
fi

if [ -d "$HOME/.librewolf" ]; then
    rsync -a --info=progress2 \
        --exclude='*/cache2/' \
        --exclude='*/Cache/' \
        "$HOME/.librewolf/" "$BACKUP_DIR/browsers/librewolf/"
    echo "   ✓ LibreWolf backed up"
fi

# Document Chromium-based browsers (already in ~/.config backup, but list them)
echo "   Chromium browsers (in ~/.config backup):"
[ -d "$HOME/.config/google-chrome" ] && echo "   ✓ Google Chrome"
[ -d "$HOME/.config/chromium" ] && echo "   ✓ Chromium"
[ -d "$HOME/.config/BraveSoftware" ] && echo "   ✓ Brave"
[ -d "$HOME/.config/vivaldi" ] && echo "   ✓ Vivaldi"
[ -d "$HOME/.config/opera" ] && echo "   ✓ Opera"
[ -d "$HOME/.config/microsoft-edge" ] && echo "   ✓ Microsoft Edge"

# Save list of browser extensions for reference
echo "# Browser Extensions Inventory" > "$BACKUP_DIR/browsers/extensions-list.txt"
echo "# Generated: $(date)" >> "$BACKUP_DIR/browsers/extensions-list.txt"
echo "" >> "$BACKUP_DIR/browsers/extensions-list.txt"

# Chrome extensions
if [ -d "$HOME/.config/google-chrome/Default/Extensions" ]; then
    echo "## Google Chrome Extensions:" >> "$BACKUP_DIR/browsers/extensions-list.txt"
    ls "$HOME/.config/google-chrome/Default/Extensions" 2>/dev/null >> "$BACKUP_DIR/browsers/extensions-list.txt"
    echo "" >> "$BACKUP_DIR/browsers/extensions-list.txt"
fi

# Brave extensions
if [ -d "$HOME/.config/BraveSoftware/Brave-Browser/Default/Extensions" ]; then
    echo "## Brave Extensions:" >> "$BACKUP_DIR/browsers/extensions-list.txt"
    ls "$HOME/.config/BraveSoftware/Brave-Browser/Default/Extensions" 2>/dev/null >> "$BACKUP_DIR/browsers/extensions-list.txt"
    echo "" >> "$BACKUP_DIR/browsers/extensions-list.txt"
fi

# Chromium extensions
if [ -d "$HOME/.config/chromium/Default/Extensions" ]; then
    echo "## Chromium Extensions:" >> "$BACKUP_DIR/browsers/extensions-list.txt"
    ls "$HOME/.config/chromium/Default/Extensions" 2>/dev/null >> "$BACKUP_DIR/browsers/extensions-list.txt"
fi

echo "   ✓ Browser profiles backed up"

# ============================================================================
# 18. CREATE RESTORE SCRIPT AND ARCHIVE
# ============================================================================
echo "[18/18] Creating backup archive..."

# Copy restore script
cp "$(dirname "$0")/restore.sh" "$BACKUP_DIR/" 2>/dev/null || true

# Calculate backup size
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

# Create compressed archive with readable date
cd "$HOME"
ARCHIVE_NAME="garuda-backup-${READABLE_DATE}.tar.gz"
tar -czf "$ARCHIVE_NAME" "$(basename "$BACKUP_DIR")"

echo "   ✓ Archive created: $HOME/$ARCHIVE_NAME"

# ============================================================================
# DAEMON MODE: Move archive to backup destination, cleanup old backups
# ============================================================================
if [ "$DAEMON_MODE" = true ]; then
    ARCHIVE="$HOME/$ARCHIVE_NAME"

    # Remove "last" from previous backup filename
    PREV_LAST=$(ls "$BACKUP_DEST"/garuda-backup-*-last.tar.gz 2>/dev/null | head -1)
    if [ -n "$PREV_LAST" ] && [ -f "$PREV_LAST" ]; then
        NEW_NAME=$(echo "$PREV_LAST" | sed 's/-last\.tar\.gz$/.tar.gz/')
        mv "$PREV_LAST" "$NEW_NAME"
        log "Renamed previous: $(basename "$PREV_LAST") -> $(basename "$NEW_NAME")"
    fi

    # Move new archive and add "last" suffix
    ARCHIVE_BASENAME=$(basename "$ARCHIVE" .tar.gz)
    FINAL_ARCHIVE="$BACKUP_DEST/${ARCHIVE_BASENAME}-last.tar.gz"
    mv "$ARCHIVE" "$FINAL_ARCHIVE"

    # Remove uncompressed backup directory
    rm -rf "$BACKUP_DIR"

    # Get backup size
    FINAL_SIZE=$(du -h "$FINAL_ARCHIVE" | cut -f1)

    # Cleanup old backups (keep only 2)
    BACKUPS_TO_DELETE=$(ls -t "$BACKUP_DEST"/garuda-backup-*.tar.gz 2>/dev/null | tail -n +3)
    if [ -n "$BACKUPS_TO_DELETE" ]; then
        echo "$BACKUPS_TO_DELETE" | while read -r old_backup; do
            log "Deleting old backup: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
    fi

    BACKUP_COUNT=$(ls -1 "$BACKUP_DEST"/garuda-backup-*.tar.gz 2>/dev/null | wc -l)
    log "SUCCESS: Backup saved to $FINAL_ARCHIVE ($FINAL_SIZE)"
    log "Cleanup complete. $BACKUP_COUNT backups remaining."
    log "=========================================="

    notify "✅ Garuda Backup Complete" "Saved: $(basename "$FINAL_ARCHIVE")\nSize: $FINAL_SIZE\nLocation: $BACKUP_DEST" "dialog-ok" "normal"

    echo ""
    echo "✓ Backup complete: $FINAL_ARCHIVE ($FINAL_SIZE)"
else
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║                    BACKUP FINISHED!                                   ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Backup directory: $BACKUP_DIR"
    echo "Backup archive:   $HOME/$ARCHIVE_NAME"
    echo "Total size:       $BACKUP_SIZE"
    echo ""
    echo "NEXT STEPS:"
    echo "1. Copy '$ARCHIVE_NAME' to external storage"
    echo "2. Install fresh Garuda KDE"
    echo "3. Extract and run restore.sh"
fi

exit 0
