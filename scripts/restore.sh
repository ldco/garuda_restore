#!/bin/bash
# ============================================================================
# Garuda KDE Linux - COMPLETE System Settings Restore Script
# ============================================================================
# This script restores ALL settings from backup to a fresh Garuda KDE install.
# Including: KDE panels, wallpapers, app configs, themes, fonts, and more.
#
# Run this script on your NEW Garuda installation AFTER first boot.
# ============================================================================

set -e

# Find the backup directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR"

# Check if this looks like a valid backup
if [ ! -f "$BACKUP_DIR/packages/explicitly-installed.txt" ]; then
    echo "ERROR: Could not find backup files in $BACKUP_DIR"
    echo "Please run this script from within the backup directory."
    exit 1
fi

# Get username for path replacements
NEW_USER=$(whoami)
NEW_HOME="$HOME"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║    Garuda KDE Linux - COMPLETE System Settings Restore Script        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Restoring from: $BACKUP_DIR"
echo "Current user:   $NEW_USER"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."
echo ""

# ============================================================================
# 1. UPDATE SYSTEM FIRST
# ============================================================================
echo "[1/17] Updating system..."
sudo pacman -Syu --noconfirm
echo "   ✓ System updated"

# ============================================================================
# 2. INSTALL CHAOTIC-AUR (if not present)
# ============================================================================
echo "[2/17] Ensuring Chaotic-AUR is configured..."

if ! grep -q "chaotic-aur" /etc/pacman.conf 2>/dev/null; then
    echo "   Installing Chaotic-AUR..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' --noconfirm
    sudo pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' --noconfirm
    echo -e '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf
    sudo pacman -Sy
fi
echo "   ✓ Chaotic-AUR configured"

# ============================================================================
# 3. INSTALL PARU (AUR helper)
# ============================================================================
echo "[3/17] Ensuring paru is installed..."

if ! command -v paru &> /dev/null; then
    echo "   Installing paru..."
    sudo pacman -S --needed base-devel git --noconfirm
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru && makepkg -si --noconfirm
    cd "$BACKUP_DIR"
fi
echo "   ✓ Paru installed"

# ============================================================================
# 4. INSTALL PACKAGES
# ============================================================================
echo "[4/17] Installing packages (this may take a while)..."

# Install native packages from official repos
echo "   Installing native packages..."
if [ -f "$BACKUP_DIR/packages/native-packages.txt" ]; then
    NATIVE_PKGS=$(cat "$BACKUP_DIR/packages/native-packages.txt" | awk '{print $1}' | tr '\n' ' ')
    sudo pacman -S --needed --noconfirm $NATIVE_PKGS 2>&1 | grep -v "warning:" || true
fi

# Install AUR packages via paru
echo "   Installing AUR packages..."
if [ -f "$BACKUP_DIR/packages/aur-packages.txt" ]; then
    while IFS= read -r line; do
        pkg=$(echo "$line" | awk '{print $1}')
        echo "   Installing: $pkg"
        paru -S --needed --noconfirm "$pkg" 2>/dev/null || echo "   ⚠ Could not install $pkg"
    done < "$BACKUP_DIR/packages/aur-packages.txt"
fi
echo "   ✓ Packages installed"

# ============================================================================
# 5. RESTORE FONTS
# ============================================================================
echo "[5/17] Restoring fonts..."

if [ -d "$BACKUP_DIR/.fonts" ]; then
    mkdir -p "$HOME/.fonts"
    cp -r "$BACKUP_DIR/.fonts/"* "$HOME/.fonts/" 2>/dev/null || true
    fc-cache -fv > /dev/null 2>&1
    echo "   ✓ Fonts restored and cache rebuilt"
else
    echo "   No fonts to restore"
fi

# ============================================================================
# 6. RESTORE ICONS AND THEMES
# ============================================================================
echo "[6/17] Restoring icons and themes..."

[ -d "$BACKUP_DIR/.icons" ] && cp -r "$BACKUP_DIR/.icons" "$HOME/"
[ -d "$BACKUP_DIR/.themes" ] && cp -r "$BACKUP_DIR/.themes" "$HOME/"

echo "   ✓ Icons and themes restored"

# ============================================================================
# 7. RESTORE ~/.config (ALL settings)
# ============================================================================
echo "[7/17] Restoring ALL application and KDE settings..."

if [ -d "$BACKUP_DIR/config" ]; then
    # Backup current config first
    if [ -d "$HOME/.config" ]; then
        mv "$HOME/.config" "$HOME/.config.backup.$(date +%s)"
    fi

    # Copy all config
    cp -r "$BACKUP_DIR/config" "$HOME/.config"

    # Fix paths in config files (replace old username with new)
    # Find the old username from config files
    OLD_HOME=$(grep -r "/home/" "$BACKUP_DIR/config" 2>/dev/null | head -1 | grep -oP '/home/[^/]+' | head -1)
    if [ -n "$OLD_HOME" ] && [ "$OLD_HOME" != "$NEW_HOME" ]; then
        echo "   Updating paths from $OLD_HOME to $NEW_HOME..."
        find "$HOME/.config" -type f -exec sed -i "s|$OLD_HOME|$NEW_HOME|g" {} \; 2>/dev/null || true
    fi

    echo "   ✓ ~/.config restored"
else
    echo "   ⚠ No config backup found"
fi

# ============================================================================
# 8. RESTORE ~/.local/share (KDE data, Konsole profiles, etc.)
# ============================================================================
echo "[8/17] Restoring KDE data and profiles..."

if [ -d "$BACKUP_DIR/local-share" ]; then
    mkdir -p "$HOME/.local/share"

    for item in "$BACKUP_DIR/local-share"/*; do
        name=$(basename "$item")
        if [ -d "$item" ]; then
            rm -rf "$HOME/.local/share/$name"
            cp -r "$item" "$HOME/.local/share/"
        elif [ -f "$item" ]; then
            cp "$item" "$HOME/.local/share/"
        fi
    done

    # Fix paths
    if [ -n "$OLD_HOME" ] && [ "$OLD_HOME" != "$NEW_HOME" ]; then
        find "$HOME/.local/share" -type f -exec sed -i "s|$OLD_HOME|$NEW_HOME|g" {} \; 2>/dev/null || true
    fi

    echo "   ✓ ~/.local/share restored"
else
    echo "   ⚠ No local-share backup found"
fi

# ============================================================================
# 9. RESTORE SSH KEYS AND SECURITY
# ============================================================================
echo "[9/17] Restoring SSH keys, GPG keys, security..."

if [ -d "$BACKUP_DIR/security/.ssh" ]; then
    cp -r "$BACKUP_DIR/security/.ssh" "$HOME/"
    chmod 700 "$HOME/.ssh"
    chmod 600 "$HOME/.ssh/"* 2>/dev/null || true
    chmod 644 "$HOME/.ssh/"*.pub 2>/dev/null || true
    echo "   ✓ SSH keys restored"
fi

if [ -d "$BACKUP_DIR/security/.gnupg" ]; then
    cp -r "$BACKUP_DIR/security/.gnupg" "$HOME/"
    chmod 700 "$HOME/.gnupg"
    echo "   ✓ GPG keys restored"
fi

[ -d "$BACKUP_DIR/security/.password-store" ] && cp -r "$BACKUP_DIR/security/.password-store" "$HOME/"

echo "   ✓ Security credentials restored"

# ============================================================================
# 10. RESTORE WALLPAPERS
# ============================================================================
echo "[10/17] Restoring wallpapers..."

if [ -d "$BACKUP_DIR/wallpapers" ]; then
    mkdir -p "$HOME/Pictures"
    cp -r "$BACKUP_DIR/wallpapers/"* "$HOME/Pictures/" 2>/dev/null || true
    echo "   ✓ Wallpapers restored to ~/Pictures/"
else
    echo "   No wallpapers to restore"
fi

# ============================================================================
# 11. RESTORE DOTFILES AND GIT CONFIG
# ============================================================================
echo "[11/17] Restoring dotfiles and git configuration..."

if [ -d "$BACKUP_DIR/dotfiles" ]; then
    for file in "$BACKUP_DIR/dotfiles"/*; do
        [ -f "$file" ] && cp "$file" "$HOME/"
    done
    for file in "$BACKUP_DIR/dotfiles"/.*; do
        [ -f "$file" ] && [ "$(basename "$file")" != "." ] && [ "$(basename "$file")" != ".." ] && cp "$file" "$HOME/"
    done
    # Git config directory
    [ -d "$BACKUP_DIR/dotfiles/git" ] && mkdir -p "$HOME/.config" && cp -r "$BACKUP_DIR/dotfiles/git" "$HOME/.config/"

    # Oh My Zsh custom plugins/themes
    if [ -d "$BACKUP_DIR/dotfiles/oh-my-zsh-custom" ]; then
        mkdir -p "$HOME/.oh-my-zsh/custom"
        cp -r "$BACKUP_DIR/dotfiles/oh-my-zsh-custom/"* "$HOME/.oh-my-zsh/custom/" 2>/dev/null || true
        echo "   ✓ Oh My Zsh custom plugins/themes restored"
    fi

    echo "   ✓ Dotfiles restored"
else
    echo "   No dotfiles to restore"
fi

# ============================================================================
# 12. RESTORE NETWORK/VPN CONNECTIONS
# ============================================================================
echo "[12/17] Restoring network and VPN connections..."

if [ -d "$BACKUP_DIR/networks/system-connections" ]; then
    sudo mkdir -p /etc/NetworkManager/system-connections
    sudo cp -r "$BACKUP_DIR/networks/system-connections/"* /etc/NetworkManager/system-connections/ 2>/dev/null || true
    sudo chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null || true
    sudo systemctl restart NetworkManager 2>/dev/null || true
    echo "   ✓ Network connections restored"
fi

[ -d "$BACKUP_DIR/networks/wireguard" ] && sudo cp -r "$BACKUP_DIR/networks/wireguard" /etc/
[ -d "$BACKUP_DIR/networks/openvpn" ] && sudo cp -r "$BACKUP_DIR/networks/openvpn" /etc/
[ -d "$BACKUP_DIR/networks/tailscale" ] && mkdir -p "$HOME/.config" && cp -r "$BACKUP_DIR/networks/tailscale" "$HOME/.config/"

echo "   ✓ VPN configurations restored"

# ============================================================================
# 13. RESTORE BLENDER ADDONS
# ============================================================================
echo "[13/17] Restoring Blender addons..."

if [ -d "$BACKUP_DIR/blender" ]; then
    mkdir -p "$HOME/.config/blender"
    for ver_dir in "$BACKUP_DIR/blender"/*; do
        [ -d "$ver_dir" ] && cp -r "$ver_dir" "$HOME/.config/blender/"
    done
    echo "   ✓ Blender addons restored"
fi

# ============================================================================
# 14. RESTORE APPLICATION DATA (GIMP, Krita, etc.)
# ============================================================================
echo "[14/17] Restoring application plugins..."

[ -d "$BACKUP_DIR/app-data/.gimp-2.10" ] && cp -r "$BACKUP_DIR/app-data/.gimp-2.10" "$HOME/"
[ -d "$BACKUP_DIR/app-data/GIMP" ] && cp -r "$BACKUP_DIR/app-data/GIMP" "$HOME/.config/"
[ -d "$BACKUP_DIR/app-data/inkscape-extensions" ] && mkdir -p "$HOME/.config/inkscape" && cp -r "$BACKUP_DIR/app-data/inkscape-extensions" "$HOME/.config/inkscape/extensions"
[ -d "$BACKUP_DIR/app-data/krita" ] && mkdir -p "$HOME/.local/share" && cp -r "$BACKUP_DIR/app-data/krita" "$HOME/.local/share/"

# Reinstall VS Code extensions
if [ -f "$BACKUP_DIR/app-data/vscode-extensions.txt" ] && command -v code &> /dev/null; then
    echo "   Installing VS Code extensions..."
    while IFS= read -r ext; do
        code --install-extension "$ext" 2>/dev/null || true
    done < "$BACKUP_DIR/app-data/vscode-extensions.txt"
fi

echo "   ✓ Application plugins restored"

# ============================================================================
# 15. RESTORE DOCKER DATA
# ============================================================================
echo "[15/18] Restoring Docker data..."

if [ -d "$BACKUP_DIR/docker" ]; then
    # Docker client config
    [ -d "$BACKUP_DIR/docker/.docker" ] && cp -r "$BACKUP_DIR/docker/.docker" "$HOME/"

    # Docker compose files
    for dir in docker compose docker-compose; do
        [ -d "$BACKUP_DIR/docker/$dir" ] && cp -r "$BACKUP_DIR/docker/$dir" "$HOME/"
    done

    # Restore Docker volumes (requires sudo and Docker running)
    if [ -f "$BACKUP_DIR/docker/volumes-backup.tar.gz" ]; then
        echo "   Found Docker volumes backup"
        read -p "   Restore Docker volumes? This requires Docker to be stopped. [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl stop docker 2>/dev/null || true
            sudo tar -xzf "$BACKUP_DIR/docker/volumes-backup.tar.gz" -C /var/lib/docker/ 2>/dev/null || true
            sudo systemctl start docker 2>/dev/null || true
            echo "   ✓ Docker volumes restored"
        fi
    fi

    echo "   ✓ Docker config restored"

    # Show info about images to pull
    if [ -f "$BACKUP_DIR/docker/images-list.txt" ]; then
        echo "   Note: Docker images list saved. To restore images, run:"
        echo "   cat $BACKUP_DIR/docker/images-list.txt | xargs -I {} docker pull {}"
    fi
else
    echo "   No Docker data to restore"
fi

# ============================================================================
# 16. INSTALL & RESTORE DEVELOPMENT ENVIRONMENTS
# ============================================================================
echo "[16/19] Installing development tools and restoring configs..."

if [ -d "$BACKUP_DIR/dev-envs" ]; then
    # Restore config files first
    [ -f "$BACKUP_DIR/dev-envs/.npmrc" ] && cp "$BACKUP_DIR/dev-envs/.npmrc" "$HOME/"
    [ -f "$BACKUP_DIR/dev-envs/.yarnrc" ] && cp "$BACKUP_DIR/dev-envs/.yarnrc" "$HOME/"
    [ -f "$BACKUP_DIR/dev-envs/.yarnrc.yml" ] && cp "$BACKUP_DIR/dev-envs/.yarnrc.yml" "$HOME/"
    [ -f "$BACKUP_DIR/dev-envs/.condarc" ] && cp "$BACKUP_DIR/dev-envs/.condarc" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.pip" ] && cp -r "$BACKUP_DIR/dev-envs/.pip" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.config/pip" ] && mkdir -p "$HOME/.config" && cp -r "$BACKUP_DIR/dev-envs/.config/pip" "$HOME/.config/"
    [ -d "$BACKUP_DIR/dev-envs/.cargo" ] && mkdir -p "$HOME/.cargo" && cp -r "$BACKUP_DIR/dev-envs/.cargo/"* "$HOME/.cargo/" 2>/dev/null || true
    [ -d "$BACKUP_DIR/dev-envs/go" ] && mkdir -p "$HOME/go" && cp -r "$BACKUP_DIR/dev-envs/go/"* "$HOME/go/" 2>/dev/null || true
    [ -d "$BACKUP_DIR/dev-envs/.config/go" ] && mkdir -p "$HOME/.config" && cp -r "$BACKUP_DIR/dev-envs/.config/go" "$HOME/.config/"
    [ -d "$BACKUP_DIR/dev-envs/.composer" ] && mkdir -p "$HOME/.composer" && cp -r "$BACKUP_DIR/dev-envs/.composer/"* "$HOME/.composer/" 2>/dev/null || true
    [ -d "$BACKUP_DIR/dev-envs/.config/composer" ] && mkdir -p "$HOME/.config/composer" && cp -r "$BACKUP_DIR/dev-envs/.config/composer/"* "$HOME/.config/composer/" 2>/dev/null || true
    [ -f "$BACKUP_DIR/dev-envs/.gemrc" ] && cp "$BACKUP_DIR/dev-envs/.gemrc" "$HOME/"
    echo "   ✓ Config files restored"

    # Install development tools based on what was backed up
    TOOLS_FILE="$BACKUP_DIR/dev-envs/installed-tools.txt"

    if [ -f "$TOOLS_FILE" ]; then
        echo "   Installing development toolchains..."

        # Node.js (via nvm)
        if grep -q "nodejs" "$TOOLS_FILE"; then
            echo "   → Installing Node.js..."
            if ! command -v nvm &>/dev/null && [ ! -d "$HOME/.nvm" ]; then
                curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
                export NVM_DIR="$HOME/.nvm"
                [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            fi
            # Install the version that was backed up
            if [ -f "$BACKUP_DIR/dev-envs/node-version.txt" ]; then
                NODE_VER=$(cat "$BACKUP_DIR/dev-envs/node-version.txt" | tr -d 'v')
                nvm install "$NODE_VER" 2>/dev/null || nvm install --lts
            else
                nvm install --lts 2>/dev/null || true
            fi
            echo "   ✓ Node.js installed"
        fi

        # Rust (via rustup)
        if grep -q "rust" "$TOOLS_FILE"; then
            echo "   → Installing Rust..."
            if ! command -v rustup &>/dev/null; then
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
            fi
            echo "   ✓ Rust installed"
        fi

        # Go
        if grep -q "go" "$TOOLS_FILE"; then
            echo "   → Installing Go..."
            if ! command -v go &>/dev/null; then
                sudo pacman -S --needed --noconfirm go 2>/dev/null || true
            fi
            echo "   ✓ Go installed"
        fi

        # Conda/Miniconda
        if grep -q "conda" "$TOOLS_FILE"; then
            echo "   → Installing Miniconda..."
            if ! command -v conda &>/dev/null && [ ! -d "$HOME/miniconda3" ]; then
                wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
                bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
                rm /tmp/miniconda.sh
                eval "$("$HOME/miniconda3/bin/conda" shell.bash hook)"
                conda init
            fi
            # Recreate conda environments from exported specs
            for env_file in "$BACKUP_DIR/dev-envs"/conda-env-*.yml; do
                if [ -f "$env_file" ]; then
                    ENV_NAME=$(basename "$env_file" .yml | sed 's/conda-env-//')
                    echo "   → Recreating conda env: $ENV_NAME"
                    conda env create -f "$env_file" -n "$ENV_NAME" 2>/dev/null || true
                fi
            done
            echo "   ✓ Miniconda installed"
        fi

        # PHP/Composer
        if grep -q "php" "$TOOLS_FILE"; then
            echo "   → Installing PHP & Composer..."
            sudo pacman -S --needed --noconfirm php composer 2>/dev/null || true
            echo "   ✓ PHP/Composer installed"
        fi

        # Ruby
        if grep -q "ruby" "$TOOLS_FILE"; then
            echo "   → Installing Ruby..."
            sudo pacman -S --needed --noconfirm ruby rubygems 2>/dev/null || true
            echo "   ✓ Ruby installed"
        fi
    fi

    echo "   ✓ Development environments installed and configured"
else
    echo "   No development environments to restore"
fi

# ============================================================================
# 17. RESTORE ICC COLOR PROFILES
# ============================================================================
echo "[17/19] Restoring ICC color profiles..."

if [ -d "$BACKUP_DIR/icc-profiles" ]; then
    mkdir -p "$HOME/.local/share/icc"
    cp -r "$BACKUP_DIR/icc-profiles/"* "$HOME/.local/share/icc/" 2>/dev/null || true
    echo "   ✓ ICC profiles restored"
fi

# ============================================================================
# 16. ENABLE SYSTEMD SERVICES + RESTORE BACKUP TIMER
# ============================================================================
echo "[18/19] Enabling systemd services and restoring backup timer..."

# Restore backup service and timer
if [ -d "$BACKUP_DIR/systemd/user-units" ]; then
    mkdir -p "$HOME/.config/systemd/user"
    cp "$BACKUP_DIR/systemd/user-units/"* "$HOME/.config/systemd/user/" 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user enable garuda-backup.timer 2>/dev/null || true
    echo "   ✓ Backup timer restored"
fi

# Restore backup scripts
if [ -d "$BACKUP_DIR/backup-scripts" ]; then
    RESTORE_SCRIPT_DIR="$HOME/.local/share/garuda-backup-scripts"
    mkdir -p "$RESTORE_SCRIPT_DIR"
    cp "$BACKUP_DIR/backup-scripts/"* "$RESTORE_SCRIPT_DIR/"
    chmod +x "$RESTORE_SCRIPT_DIR/"*.sh
    echo "   ✓ Backup scripts restored to $RESTORE_SCRIPT_DIR"
fi

# User services
if [ -f "$BACKUP_DIR/systemd/user-services.txt" ]; then
    while IFS= read -r service; do
        [ -n "$service" ] && systemctl --user enable "$service" 2>/dev/null || true
    done < "$BACKUP_DIR/systemd/user-services.txt"
fi

# System services
if [ -f "$BACKUP_DIR/systemd/system-services.txt" ]; then
    while IFS= read -r service; do
        [ -n "$service" ] && sudo systemctl enable "$service" 2>/dev/null || true
    done < "$BACKUP_DIR/systemd/system-services.txt"
fi

echo "   ✓ Systemd services enabled"

# ============================================================================
# 17. OPTIONAL: RESTORE SYSTEM CONFIGS
# ============================================================================
echo ""
read -p "[19/19] Restore system configs (samba, grub, network, docker)? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Restoring system configs..."

    [ -f "$BACKUP_DIR/system/smb.conf" ] && sudo cp "$BACKUP_DIR/system/smb.conf" /etc/samba/
    [ -f "$BACKUP_DIR/system/grub" ] && sudo cp "$BACKUP_DIR/system/grub" /etc/default/ && sudo update-grub 2>/dev/null || true
    [ -f "$BACKUP_DIR/system/hosts" ] && sudo cp "$BACKUP_DIR/system/hosts" /etc/
    [ -f "$BACKUP_DIR/system/environment" ] && sudo cp "$BACKUP_DIR/system/environment" /etc/
    [ -f "$BACKUP_DIR/system/locale.conf" ] && sudo cp "$BACKUP_DIR/system/locale.conf" /etc/
    [ -f "$BACKUP_DIR/system/vconsole.conf" ] && sudo cp "$BACKUP_DIR/system/vconsole.conf" /etc/
    [ -f "$BACKUP_DIR/system/daemon.json" ] && sudo mkdir -p /etc/docker && sudo cp "$BACKUP_DIR/system/daemon.json" /etc/docker/
    [ -d "$BACKUP_DIR/system/modprobe.d" ] && sudo cp -r "$BACKUP_DIR/system/modprobe.d/"* /etc/modprobe.d/
    [ -d "$BACKUP_DIR/system/rules.d" ] && sudo cp -r "$BACKUP_DIR/system/rules.d/"* /etc/udev/rules.d/
    [ -d "$BACKUP_DIR/system/xorg.conf.d" ] && sudo mkdir -p /etc/X11/xorg.conf.d && sudo cp -r "$BACKUP_DIR/system/xorg.conf.d/"* /etc/X11/xorg.conf.d/

    echo "   ✓ System configs restored"
fi

# ============================================================================
# 20. FINAL SYSTEM UPDATE
# ============================================================================
echo ""
echo "[20/20] Running final system update..."
echo "   Updating all packages to latest versions..."

# Full system update with paru (includes AUR)
if command -v paru &>/dev/null; then
    paru -Syu --noconfirm 2>&1 | tail -20
else
    sudo pacman -Syu --noconfirm 2>&1 | tail -20
fi

# Update Flatpak apps if installed
if command -v flatpak &>/dev/null; then
    echo "   Updating Flatpak apps..."
    flatpak update -y 2>/dev/null || true
fi

# Rebuild font cache
echo "   Rebuilding font cache..."
fc-cache -fv > /dev/null 2>&1

# Update desktop database
echo "   Updating desktop database..."
update-desktop-database ~/.local/share/applications 2>/dev/null || true

# Update icon cache
echo "   Updating icon cache..."
gtk-update-icon-cache -f -t ~/.icons 2>/dev/null || true
gtk-update-icon-cache -f -t ~/.local/share/icons 2>/dev/null || true

echo "   ✓ System fully updated"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║            ULTIMATE COMPLETE RESTORE FINISHED!                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "WHAT WAS RESTORED:"
echo "  ✓ All packages (pacman + AUR) - UPDATED TO LATEST"
echo "  ✓ ALL KDE/Plasma settings (panels, widgets, effects, animations)"
echo "  ✓ ALL application configs with browser profiles & history"
echo "  ✓ SSH keys (~/.ssh)"
echo "  ✓ GPG keys (~/.gnupg)"
echo "  ✓ Network/VPN connections (WiFi, WireGuard, OpenVPN)"
echo "  ✓ Docker (config, volumes, compose files)"
echo "  ✓ Development tools (Node.js, Rust, Go, Python/Conda, etc.)"
echo "  ✓ Clipboard history"
echo "  ✓ Wallpapers"
echo "  ✓ Fonts and ICC color profiles"
echo "  ✓ Icons and themes"
echo "  ✓ Git configuration"
echo "  ✓ Shell configs + history (Zsh, Fish, Bash)"
echo "  ✓ Zsh: Oh My Zsh plugins, Powerlevel10k config"
echo "  ✓ Blender, GIMP, Krita, Inkscape plugins"
echo "  ✓ VS Code extensions"
echo "  ✓ Daily backup timer (auto-configured!)"
echo "  ✓ Systemd services"
echo "  ✓ System updated to latest packages"
echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  IMPORTANT: You MUST log out and log back in (or reboot) for         ║"
echo "║  all KDE settings to take effect!                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Run: sudo reboot"
echo ""
echo "After reboot:"
echo "  • Your system should look exactly like before!"
echo "  • Daily backups will run automatically"
echo "  • If panels don't appear correctly:"
echo "      kquitapp6 plasmashell && kstart6 plasmashell"
echo ""

