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
# 16. RESTORE DEVELOPMENT ENVIRONMENTS
# ============================================================================
echo "[16/19] Restoring development environments..."

if [ -d "$BACKUP_DIR/dev-envs" ]; then
    # Node.js / NPM / Yarn
    [ -d "$BACKUP_DIR/dev-envs/.npm" ] && cp -r "$BACKUP_DIR/dev-envs/.npm" "$HOME/"
    [ -f "$BACKUP_DIR/dev-envs/.npmrc" ] && cp "$BACKUP_DIR/dev-envs/.npmrc" "$HOME/"
    [ -f "$BACKUP_DIR/dev-envs/.yarnrc" ] && cp "$BACKUP_DIR/dev-envs/.yarnrc" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.yarn" ] && cp -r "$BACKUP_DIR/dev-envs/.yarn" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.nvm" ] && cp -r "$BACKUP_DIR/dev-envs/.nvm" "$HOME/"

    # Python / Conda / Pip
    [ -d "$BACKUP_DIR/dev-envs/.conda" ] && cp -r "$BACKUP_DIR/dev-envs/.conda" "$HOME/"
    [ -f "$BACKUP_DIR/dev-envs/.condarc" ] && cp "$BACKUP_DIR/dev-envs/.condarc" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/virtualenvs" ] && mkdir -p "$HOME/.local/share" && cp -r "$BACKUP_DIR/dev-envs/virtualenvs" "$HOME/.local/share/"
    [ -d "$BACKUP_DIR/dev-envs/.pyenv" ] && cp -r "$BACKUP_DIR/dev-envs/.pyenv" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.poetry" ] && cp -r "$BACKUP_DIR/dev-envs/.poetry" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.pip" ] && cp -r "$BACKUP_DIR/dev-envs/.pip" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/conda-envs" ] && mkdir -p "$HOME/miniconda3" && cp -r "$BACKUP_DIR/dev-envs/conda-envs" "$HOME/miniconda3/envs"

    # Rust / Cargo
    [ -d "$BACKUP_DIR/dev-envs/.cargo" ] && cp -r "$BACKUP_DIR/dev-envs/.cargo" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.rustup" ] && cp -r "$BACKUP_DIR/dev-envs/.rustup" "$HOME/"

    # Go
    [ -d "$BACKUP_DIR/dev-envs/go" ] && cp -r "$BACKUP_DIR/dev-envs/go" "$HOME/"

    # PHP / Composer
    [ -d "$BACKUP_DIR/dev-envs/.composer" ] && cp -r "$BACKUP_DIR/dev-envs/.composer" "$HOME/"

    # Ruby / Gem
    [ -d "$BACKUP_DIR/dev-envs/.gem" ] && cp -r "$BACKUP_DIR/dev-envs/.gem" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.rbenv" ] && cp -r "$BACKUP_DIR/dev-envs/.rbenv" "$HOME/"
    [ -d "$BACKUP_DIR/dev-envs/.rvm" ] && cp -r "$BACKUP_DIR/dev-envs/.rvm" "$HOME/"

    echo "   ✓ Development environments restored"
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

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║            ULTIMATE COMPLETE RESTORE FINISHED!                        ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "WHAT WAS RESTORED:"
echo "  ✓ All packages (pacman + AUR)"
echo "  ✓ ALL KDE/Plasma settings (panels, widgets, effects, animations)"
echo "  ✓ ALL application configs with browser profiles & history"
echo "  ✓ SSH keys (~/.ssh)"
echo "  ✓ GPG keys (~/.gnupg)"
echo "  ✓ Network/VPN connections (WiFi, WireGuard, OpenVPN)"
echo "  ✓ Docker (config, volumes, compose files)"
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

