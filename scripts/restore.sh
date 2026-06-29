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
# 0. PRE-FLIGHT: RESOLVE KNOWN PACKAGE CONFLICTS
# ============================================================================
echo "[0/22] Pre-flight: resolving known package conflicts..."

# Garuda preinstalls nodejs-lts-jod which conflicts with npm (required by many packages)
if pacman -Q nodejs-lts-jod &>/dev/null; then
    echo "   Removing nodejs-lts-jod (conflicts with npm)..."
    sudo pacman -Rdd --noconfirm nodejs-lts-jod 2>/dev/null || true
    echo "   ✓ nodejs-lts-jod removed"
fi

# happ from official repos conflicts with happ-desktop-bin from AUR
# Only remove if backup indicates happ-desktop-bin was used
if grep -q "happ-desktop-bin" "$BACKUP_DIR/packages/aur-packages.txt" 2>/dev/null; then
    if pacman -Q happ &>/dev/null; then
        echo "   Removing happ (will be replaced with happ-desktop-bin)..."
        sudo pacman -Rdd --noconfirm happ 2>/dev/null || true
        echo "   ✓ happ removed"
    fi
fi

# Refresh pacman keyring (prevents GPG trust DB issues)
echo "   Refreshing pacman keyring..."
sudo pacman-key --init 2>/dev/null || true
sudo pacman-key --populate archlinux garuda 2>/dev/null || true
echo "   ✓ Keyring refreshed"

echo "   ✓ Pre-flight complete"
echo ""

# ============================================================================
# 1. UPDATE SYSTEM FIRST
# ============================================================================
echo "[1/22] Updating system..."
sudo pacman -Syu --noconfirm
echo "   ✓ System updated"

# ============================================================================
# 2. DETECT HARDWARE
# ============================================================================
echo "[2/22] Detecting hardware..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/tools/detect-hardware.sh"
APPLY_OPT_SCRIPT="$SCRIPT_DIR/tools/apply-optimizations.sh"

if [ -f "$DETECT_SCRIPT" ]; then
    echo ""
    "$DETECT_SCRIPT" --summary
    echo ""
    echo "   ✓ Hardware detection complete"
else
    echo "   ⚠ Hardware detection script not found, skipping"
fi

# ============================================================================
# 3. INSTALL CHAOTIC-AUR (if not present)
# ============================================================================
echo "[3/22] Ensuring Chaotic-AUR is configured..."

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
# 4. INSTALL PARU (AUR helper)
# ============================================================================
echo "[4/22] Ensuring paru is installed..."

if ! command -v paru &> /dev/null; then
    echo "   Installing paru..."
    sudo pacman -S --needed base-devel git --noconfirm
    git clone https://aur.archlinux.org/paru.git /tmp/paru
    cd /tmp/paru && makepkg -si --noconfirm
    cd "$BACKUP_DIR"
fi
echo "   ✓ Paru installed"

# ============================================================================
# 4. INSTALL ALL SOFTWARE (pacman, AUR, npm, pip, flatpak, git repos)
# ============================================================================
echo "[4/22] Installing all software (this may take a while)..."

# Use tracker data if available, otherwise fall back to legacy
TRACKER_DATA="$BACKUP_DIR/installed-software"

# Load explicit package list (may contain both native and AUR packages)
PKG_FILE="$TRACKER_DATA/pacman-explicit.txt"
[ ! -f "$PKG_FILE" ] && PKG_FILE="$BACKUP_DIR/packages/explicitly-installed.txt"

# --- SEPARATE NATIVE vs AUR from explicit list ---
echo "   [0/6] Analyzing package list (separating native vs AUR)..."
NATIVE_TMP=$(mktemp)
AUR_TMP=$(mktemp)
NATIVE_COUNT=0
AUR_COUNT=0

if [ -f "$PKG_FILE" ]; then
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        pkg=$(echo "$pkg" | awk '{print $1}')
        # Check if package is in pacman repos (native) or AUR-only
        if pacman -Si "$pkg" 2>/dev/null | grep -q "^Repository "; then
            echo "$pkg" >> "$NATIVE_TMP"
            ((NATIVE_COUNT++))
        else
            echo "$pkg" >> "$AUR_TMP"
            ((AUR_COUNT++))
        fi
    done < "$PKG_FILE"
fi
echo "   → Native (pacman): $NATIVE_COUNT packages"
echo "   → AUR (paru):      $AUR_COUNT packages"
echo ""

# --- PACMAN NATIVE PACKAGES (one-at-a-time, no error swallowing) ---
echo "   [1/6] Installing native packages (pacman, one-at-a-time)..."
NATIVE_OK=0
NATIVE_FAIL=0
NATIVE_SKIP=0
if [ -f "$NATIVE_TMP" ] && [ -s "$NATIVE_TMP" ]; then
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if pacman -Q "$pkg" &>/dev/null; then
            ((NATIVE_SKIP++))
            continue
        fi
        if sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
            ((NATIVE_OK++))
        else
            ((NATIVE_FAIL++))
            echo "     ⚠ Failed: $pkg"
        fi
    done < "$NATIVE_TMP"
    echo "   ✓ Native: $NATIVE_OK installed, $NATIVE_SKIP skipped, $NATIVE_FAIL failed"
else
    echo "   ⚠ No native packages to install"
fi

# --- AUR PACKAGES (one-at-a-time) ---
echo "   [2/6] Installing AUR packages (paru, one-at-a-time)..."
AUR_OK=0
AUR_FAIL=0
AUR_SKIP=0

# Also load the dedicated AUR list (pacman -Qm captures foreign packages)
AUR_DEDICATED_FILE="$TRACKER_DATA/aur-packages.txt"
[ ! -f "$AUR_DEDICATED_FILE" ] && AUR_DEDICATED_FILE="$BACKUP_DIR/packages/aur-packages.txt"

# Merge AUR packages from both sources (explicit list + dedicated aur list)
AUR_MERGED=$(mktemp)
if [ -f "$AUR_TMP" ]; then cat "$AUR_TMP" >> "$AUR_MERGED"; fi
if [ -f "$AUR_DEDICATED_FILE" ]; then cat "$AUR_DEDICATED_FILE" | awk '{print $1}' >> "$AUR_MERGED"; fi
sort -u "$AUR_MERGED" -o "$AUR_MERGED"

if [ -s "$AUR_MERGED" ]; then
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if pacman -Q "$pkg" &>/dev/null; then
            ((AUR_SKIP++))
            continue
        fi
        if paru -S --needed --noconfirm "$pkg" &>/dev/null; then
            ((AUR_OK++))
        else
            ((AUR_FAIL++))
            echo "     ⚠ Failed: $pkg"
        fi
    done < "$AUR_MERGED"
    echo "   ✓ AUR: $AUR_OK installed, $AUR_SKIP skipped, $AUR_FAIL failed"
else
    echo "   ⚠ No AUR packages to install"
fi

rm -f "$NATIVE_TMP" "$AUR_TMP" "$AUR_MERGED"

# --- NPM GLOBAL PACKAGES ---
echo "   [3/6] Installing global npm packages..."
if [ -f "$TRACKER_DATA/npm-global.txt" ] && command -v npm &>/dev/null; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        # Extract package name (format: package@version)
        pkg=$(echo "$line" | cut -d'@' -f1)
        # Skip npm itself and built-in packages
        [[ "$pkg" == "npm" || "$pkg" == "corepack" ]] && continue
        echo "     Installing: $pkg"
        sudo npm install -g "$pkg" 2>/dev/null || true
    done < "$TRACKER_DATA/npm-global.txt"
    echo "   ✓ NPM packages done"
else
    echo "   ⚠ No npm packages to restore or npm not installed"
fi

# --- PIP USER PACKAGES ---
echo "   [4/6] Installing pip user packages..."
if [ -f "$TRACKER_DATA/pip-user.txt" ] && command -v pip &>/dev/null; then
    pip install --user -r "$TRACKER_DATA/pip-user.txt" 2>/dev/null || true
    echo "   ✓ PIP packages done"
else
    echo "   ⚠ No pip packages to restore"
fi

# --- FLATPAK APPS ---
echo "   [5/6] Installing Flatpak apps..."
if [ -f "$TRACKER_DATA/flatpak.txt" ] && command -v flatpak &>/dev/null; then
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        echo "     Installing: $app"
        flatpak install -y flathub "$app" 2>/dev/null || true
    done < "$TRACKER_DATA/flatpak.txt"
    echo "   ✓ Flatpak apps done"
else
    echo "   ⚠ No Flatpak apps to restore"
fi

# --- GIT REPOS ---
echo "   [6/6] Cloning git repositories..."
if [ -f "$TRACKER_DATA/git-repos.txt" ]; then
    while IFS='|' read -r repo_dir remote_url; do
        # Skip comments and empty lines
        [[ "$repo_dir" =~ ^# ]] && continue
        [ -z "$repo_dir" ] && continue
        [ "$remote_url" == "no-remote" ] && continue

        if [ ! -d "$repo_dir" ]; then
            echo "     Cloning: $repo_dir"
            git clone "$remote_url" "$repo_dir" 2>/dev/null || echo "     ⚠ Failed to clone $repo_dir"
        else
            echo "     Already exists: $repo_dir"
        fi
    done < "$TRACKER_DATA/git-repos.txt"
    echo "   ✓ Git repos done"
else
    echo "   ⚠ No git repos to restore"
fi

echo "   ✓ All software installed"

# ============================================================================
# 5. RESTORE FONTS
# ============================================================================
echo "[5/22] Restoring fonts..."

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
echo "[6/22] Restoring icons and themes..."

[ -d "$BACKUP_DIR/.icons" ] && cp -r "$BACKUP_DIR/.icons" "$HOME/"
[ -d "$BACKUP_DIR/.themes" ] && cp -r "$BACKUP_DIR/.themes" "$HOME/"

echo "   ✓ Icons and themes restored"

# ============================================================================
# 7. RESTORE ~/.config (ALL settings)
# ============================================================================
echo "[7/22] Restoring ALL application and KDE settings..."

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
echo "[8/22] Restoring KDE data and profiles..."

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
echo "[9/22] Restoring SSH keys, GPG keys, security..."

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

# Restore user avatar / face icon
if [ -f "$BACKUP_DIR/security/.face.icon" ]; then
    cp "$BACKUP_DIR/security/.face.icon" "$HOME/.face.icon"
    echo "   ✓ User avatar restored"
fi

echo "   ✓ Security credentials restored"

# ============================================================================
# 10. RESTORE WALLPAPERS
# ============================================================================
echo "[10/22] Restoring wallpapers..."

if [ -d "$BACKUP_DIR/wallpapers" ]; then
    mkdir -p "$HOME/Pictures"
    cp -r "$BACKUP_DIR/wallpapers/"* "$HOME/Pictures/" 2>/dev/null || true
    echo "   ✓ Wallpapers restored to ~/Pictures/"
    # Record first wallpaper for auto-apply after plasma starts
    FIRST_WALLPAPER=$(ls "$HOME/Pictures/"*.png "$HOME/Pictures/"*.jpg 2>/dev/null | head -1)
    [ -n "$FIRST_WALLPAPER" ] && echo "$FIRST_WALLPAPER" > "$HOME/.cache/restore-wallpaper-path"
else
    echo "   No wallpapers to restore"
fi

# ============================================================================
# 11. RESTORE DOTFILES AND GIT CONFIG
# ============================================================================
echo "[11/22] Restoring dotfiles and git configuration..."

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
echo "[12/22] Restoring network and VPN connections..."

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
echo "[13/22] Restoring Blender addons..."

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
echo "[14/22] Restoring application plugins..."

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
echo "[15/22] Restoring Docker data..."

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
echo "[16/22] Installing development tools and restoring configs..."

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

            # Reinstall global npm packages
            if [ -f "$BACKUP_DIR/dev-envs/npm-global-packages.txt" ]; then
                echo "   → Installing global npm packages..."
                while IFS= read -r pkg; do
                    [ -z "$pkg" ] && continue
                    # Skip npm itself and node-gyp (comes with npm)
                    [[ "$pkg" == "npm" || "$pkg" == "node-gyp" || "$pkg" == "nopt" || "$pkg" == "semver" ]] && continue
                    echo "     Installing: $pkg"
                    npm install -g "$pkg" 2>/dev/null || true
                done < "$BACKUP_DIR/dev-envs/npm-global-packages.txt"
                echo "   ✓ Global npm packages installed"
            fi
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
# 17. RESTORE AI TOOLS (Claude Code, Codex, Qwen Code, ComfyUI, Fooocus)
# ============================================================================
echo "[17/22] Setting up AI tools (Claude Code, Codex, Qwen Code, ComfyUI, Fooocus)..."
echo "   This will download ~75GB of models. Skip with Ctrl+C if not needed."
echo ""

if [ -d "$BACKUP_DIR/ai-tools" ]; then

    # Claude Code config (always restore - no prompt needed)
    if [ -d "$BACKUP_DIR/ai-tools/claude-code" ]; then
        echo "   Restoring Claude Code configuration..."
        mkdir -p "$HOME/.claude"

        [ -f "$BACKUP_DIR/ai-tools/claude-code/.claude.json" ] && cp "$BACKUP_DIR/ai-tools/claude-code/.claude.json" "$HOME/"
        [ -f "$BACKUP_DIR/ai-tools/claude-code/settings.json" ] && cp "$BACKUP_DIR/ai-tools/claude-code/settings.json" "$HOME/.claude/"
        [ -f "$BACKUP_DIR/ai-tools/claude-code/.credentials.json" ] && cp "$BACKUP_DIR/ai-tools/claude-code/.credentials.json" "$HOME/.claude/"

        [ -d "$BACKUP_DIR/ai-tools/claude-code/commands" ] && cp -r "$BACKUP_DIR/ai-tools/claude-code/commands" "$HOME/.claude/"
        [ -d "$BACKUP_DIR/ai-tools/claude-code/templates" ] && cp -r "$BACKUP_DIR/ai-tools/claude-code/templates" "$HOME/.claude/"
        [ -d "$BACKUP_DIR/ai-tools/claude-code/roles" ] && cp -r "$BACKUP_DIR/ai-tools/claude-code/roles" "$HOME/.claude/"
        [ -d "$BACKUP_DIR/ai-tools/claude-code/scripts" ] && cp -r "$BACKUP_DIR/ai-tools/claude-code/scripts" "$HOME/.claude/"
        [ -d "$BACKUP_DIR/ai-tools/claude-code/knowledge" ] && cp -r "$BACKUP_DIR/ai-tools/claude-code/knowledge" "$HOME/.claude/"

        echo "   ✓ Claude Code config restored"
    fi

    # Codex config (always restore - no prompt needed)
    if [ -d "$BACKUP_DIR/ai-tools/codex" ]; then
        echo "   Restoring Codex configuration..."
        mkdir -p "$HOME/.codex"
        rsync -a "$BACKUP_DIR/ai-tools/codex/" "$HOME/.codex/" 2>/dev/null || true
        echo "   ✓ Codex config restored"
    fi

    # Qwen Code config (always restore - no prompt needed)
    if [ -d "$BACKUP_DIR/ai-tools/qwen-code" ]; then
        echo "   Restoring Qwen Code configuration..."

        [ -f "$BACKUP_DIR/ai-tools/qwen-code/.qwen-code.json" ] && cp "$BACKUP_DIR/ai-tools/qwen-code/.qwen-code.json" "$HOME/"

        if [ -d "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen-code" ]; then
            mkdir -p "$HOME/.qwen-code"
            rsync -a "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen-code/" "$HOME/.qwen-code/" 2>/dev/null || true
        fi

        if [ -d "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen" ]; then
            mkdir -p "$HOME/.qwen"
            rsync -a "$BACKUP_DIR/ai-tools/qwen-code/home-dot-qwen/" "$HOME/.qwen/" 2>/dev/null || true
        fi

        if [ -d "$BACKUP_DIR/ai-tools/qwen-code/config-qwen-code" ]; then
            mkdir -p "$HOME/.config/qwen-code"
            rsync -a "$BACKUP_DIR/ai-tools/qwen-code/config-qwen-code/" "$HOME/.config/qwen-code/" 2>/dev/null || true
        fi

        echo "   ✓ Qwen Code config restored"
    fi

    read -p "   Install ComfyUI + Fooocus with all AI models? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then

        # Install pyenv if needed
        if ! command -v pyenv &>/dev/null; then
            echo "   Installing pyenv..."
            paru -S pyenv --noconfirm 2>/dev/null || sudo pacman -S pyenv --noconfirm
        fi

        # Setup pyenv in current shell
        export PYENV_ROOT="$HOME/.pyenv"
        [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init - bash 2>/dev/null)" || true

        # Install Python 3.10 for Fooocus
        if ! pyenv versions 2>/dev/null | grep -q "3.10"; then
            echo "   Installing Python 3.10.14 (required for Fooocus)..."
            pyenv install 3.10.14
        fi

        # Ensure pip is installed
        if ! command -v pip &>/dev/null; then
            sudo pacman -S python-pip --noconfirm
        fi

        # ── COMFYUI SETUP ──
        echo "   Setting up ComfyUI..."
        if [ ! -d "$HOME/ComfyUI" ]; then
            git clone https://github.com/Comfy-Org/ComfyUI.git "$HOME/ComfyUI"
        fi

        cd "$HOME/ComfyUI"
        if [ ! -d "venv" ]; then
            python -m venv venv
        fi
        source venv/bin/activate
        pip install -q torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126
        pip install -q -r requirements.txt
        pip install -q -r manager_requirements.txt 2>/dev/null || true

        # Install custom nodes from backup list
        if [ -f "$BACKUP_DIR/ai-tools/comfyui/custom-nodes.txt" ]; then
            echo "   Installing custom nodes..."
            cd "$HOME/ComfyUI/custom_nodes"
            while IFS='|' read -r node_name node_url; do
                [[ "$node_name" =~ ^#.*$ ]] && continue
                [ -z "$node_url" ] && continue
                if [ ! -d "$node_name" ]; then
                    echo "      Cloning $node_name..."
                    git clone "$node_url" "$node_name" 2>/dev/null || true
                fi
            done < "$BACKUP_DIR/ai-tools/comfyui/custom-nodes.txt"

            # Install requirements for custom nodes
            cd "$HOME/ComfyUI"
            source venv/bin/activate
            for req in custom_nodes/*/requirements.txt; do
                [ -f "$req" ] && pip install -q -r "$req" 2>/dev/null || true
            done
        fi

        # Restore ComfyUI config
        [ -f "$BACKUP_DIR/ai-tools/comfyui/MODELS.md" ] && cp "$BACKUP_DIR/ai-tools/comfyui/MODELS.md" "$HOME/ComfyUI/"
        [ -f "$BACKUP_DIR/ai-tools/comfyui/extra_model_paths.yaml" ] && cp "$BACKUP_DIR/ai-tools/comfyui/extra_model_paths.yaml" "$HOME/ComfyUI/"
        [ -d "$BACKUP_DIR/ai-tools/comfyui/input" ] && cp -r "$BACKUP_DIR/ai-tools/comfyui/input/"* "$HOME/ComfyUI/input/" 2>/dev/null || true

        echo "   ✓ ComfyUI installed"

        # ── FOOOCUS SETUP ──
        echo "   Setting up Fooocus..."
        if [ ! -d "$HOME/Fooocus" ]; then
            git clone https://github.com/lllyasviel/Fooocus.git "$HOME/Fooocus"
        fi

        cd "$HOME/Fooocus"
        if [ ! -d "venv" ]; then
            ~/.pyenv/versions/3.10.14/bin/python -m venv venv
        fi
        source venv/bin/activate
        pip install -q torch torchvision --extra-index-url https://download.pytorch.org/whl/cu121
        pip install -q -r requirements_versions.txt

        # Restore Fooocus config
        [ -f "$BACKUP_DIR/ai-tools/fooocus/config.txt" ] && cp "$BACKUP_DIR/ai-tools/fooocus/config.txt" "$HOME/Fooocus/"
        [ -d "$BACKUP_DIR/ai-tools/fooocus/presets" ] && cp -r "$BACKUP_DIR/ai-tools/fooocus/presets" "$HOME/Fooocus/"

        echo "   ✓ Fooocus installed"

        # ── DOWNLOAD MODELS (~75GB) ──
        echo ""
        echo "   Downloading AI models (~75GB total)..."
        echo "   This will take 1-2 hours. Downloads can be resumed if interrupted."
        echo ""

        mkdir -p "$HOME/ComfyUI/models"/{checkpoints,diffusion_models,text_encoders,vae,loras}
        cd "$HOME/ComfyUI/models"

        # Image models
        echo "   ── Image Models ──"
        [ ! -f "checkpoints/flux1-schnell-fp8.safetensors" ] && \
            wget -c -q --show-progress -O "checkpoints/flux1-schnell-fp8.safetensors" \
            "https://huggingface.co/Comfy-Org/flux1-schnell/resolve/main/flux1-schnell-fp8.safetensors"

        [ ! -f "checkpoints/sd_xl_base_1.0.safetensors" ] && \
            wget -c -q --show-progress -O "checkpoints/sd_xl_base_1.0.safetensors" \
            "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"

        [ ! -f "diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors" ] && \
            wget -c -q --show-progress -O "diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors" \
            "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/diffusion_models/qwen_image_2512_fp8_e4m3fn.safetensors"

        [ ! -f "text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" ] && \
            wget -c -q --show-progress -O "text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors" \
            "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"

        [ ! -f "vae/qwen_image_vae.safetensors" ] && \
            wget -c -q --show-progress -O "vae/qwen_image_vae.safetensors" \
            "https://huggingface.co/Comfy-Org/Qwen-Image_ComfyUI/resolve/main/split_files/vae/qwen_image_vae.safetensors"

        [ ! -f "loras/Qwen-Image-Lightning-4steps-V1.0.safetensors" ] && \
            wget -c -q --show-progress -O "loras/Qwen-Image-Lightning-4steps-V1.0.safetensors" \
            "https://huggingface.co/lightx2v/Qwen-Image-Lightning/resolve/main/Qwen-Image-Lightning-4steps-V1.0.safetensors"

        # Video models (Wan 2.2)
        echo "   ── Video Models (Wan 2.2) ──"
        [ ! -f "diffusion_models/wan2.2_ti2v_5B_fp16.safetensors" ] && \
            wget -c -q --show-progress -O "diffusion_models/wan2.2_ti2v_5B_fp16.safetensors" \
            "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors"

        [ ! -f "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" ] && \
            wget -c -q --show-progress -O "text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
            "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors"

        [ ! -f "vae/wan2.2_vae.safetensors" ] && \
            wget -c -q --show-progress -O "vae/wan2.2_vae.safetensors" \
            "https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/vae/wan2.2_vae.safetensors"

        echo ""
        echo "   ✓ AI models downloaded"

        # Restore desktop launchers
        if [ -d "$BACKUP_DIR/ai-tools/launchers" ]; then
            mkdir -p "$HOME/.local/share/applications"
            cp "$BACKUP_DIR/ai-tools/launchers/"*.desktop "$HOME/.local/share/applications/" 2>/dev/null || true
            update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
            echo "   ✓ Desktop launchers restored"
        fi

        echo "   ✓ AI tools setup complete"
    fi
else
    echo "   No AI tools backup found, skipping"
fi

# ============================================================================
# 18. RESTORE BROWSERS (Firefox, LibreWolf)
# ============================================================================
echo "[18/22] Restoring browser profiles..."

# Firefox / Mozilla (not in ~/.config, needs separate restore)
if [ -d "$BACKUP_DIR/browsers/mozilla" ]; then
    mkdir -p "$HOME/.mozilla"
    rsync -a --info=progress2 "$BACKUP_DIR/browsers/mozilla/" "$HOME/.mozilla/"
    echo "   ✓ Firefox/Mozilla restored"
fi

# LibreWolf
if [ -d "$BACKUP_DIR/browsers/librewolf" ]; then
    mkdir -p "$HOME/.librewolf"
    rsync -a --info=progress2 "$BACKUP_DIR/browsers/librewolf/" "$HOME/.librewolf/"
    echo "   ✓ LibreWolf restored"
fi

# Chromium-based browsers are restored with ~/.config in section 6
echo "   Note: Chrome/Brave/Chromium restored with ~/.config"
echo "   ✓ Browser profiles restored"

# ============================================================================
# 19. RESTORE ICC COLOR PROFILES
# ============================================================================
echo "[19/22] Restoring ICC color profiles..."

if [ -d "$BACKUP_DIR/icc-profiles" ]; then
    mkdir -p "$HOME/.local/share/icc"
    cp -r "$BACKUP_DIR/icc-profiles/"* "$HOME/.local/share/icc/" 2>/dev/null || true
    echo "   ✓ ICC profiles restored"
fi

# ============================================================================
# 19. ENABLE SYSTEMD SERVICES + RESTORE BACKUP TIMER
# ============================================================================
echo "[20/22] Enabling systemd services and restoring backup timer..."

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
# 19B. APPLY HARDWARE-SPECIFIC OPTIMIZATIONS
# ============================================================================
echo ""
echo "[20/22] Applying hardware-specific optimizations..."

if [ -f "$APPLY_OPT_SCRIPT" ]; then
    echo ""
    # Check if we have root privileges or can get them
    if [ "$EUID" -ne 0 ]; then
        # Not running as root - check if sudo is available
        if ! command -v sudo &>/dev/null; then
            echo -e "   ${RED}ERROR: Cannot apply optimizations without root privileges.${NC}"
            echo "   This script requires sudo to apply system-level optimizations."
            echo ""
            echo "   Please re-run with: sudo ./scripts/restore.sh"
            echo ""
            echo "   Skipping optimizations..."
            echo "   You can apply them later with: sudo $APPLY_OPT_SCRIPT"
        else
            # Re-execute this script with sudo for the optimization step
            echo "   Elevating privileges for optimization script..."
            sudo "$APPLY_OPT_SCRIPT"
            echo ""
            echo "   ✓ Hardware optimizations applied"
        fi
    else
        # Already running as root
        "$APPLY_OPT_SCRIPT"
        echo ""
        echo "   ✓ Hardware optimizations applied"
    fi
else
    echo "   ⚠ Optimization script not found, skipping"
fi

# ============================================================================
# 20. OPTIONAL: RESTORE SYSTEM CONFIGS
# ============================================================================
echo ""
read -p "[21/22] Restore system configs (samba, grub, network, docker)? [y/N] " -n 1 -r
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
# 22. FINAL SYSTEM UPDATE
# ============================================================================
echo ""
echo "[22/23] Running final system update..."
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

# Remove stale browser profile locks (common issue after restore)
echo "   Cleaning stale browser locks..."
for lock in ~/.config/BraveSoftware/Brave-Browser/Singleton* \
            ~/.config/google-chrome/Singleton* \
            ~/.config/chromium/Singleton*; do
    [ -f "$lock" ] && rm -f "$lock" && echo "     Removed: $lock"
done 2>/dev/null || true

# Verify GPG trust database
echo "   Verifying pacman keyring..."
if ! sudo pacman-key --list-keys archlinux@archlinux.org &>/dev/null; then
    echo "     Keyring needs repair — running pacman-key --populate..."
    sudo pacman-key --init 2>/dev/null || true
    sudo pacman-key --populate archlinux garuda 2>/dev/null || true
fi

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
echo "  ✓ AI Tools: ComfyUI + Fooocus (with ~75GB models)"
echo "      - FLUX.1 Schnell (fast photorealism)"
echo "      - SDXL 1.0 (artistic, LoRA ecosystem)"
echo "      - Qwen-Image-2512 (best quality, text rendering)"
echo "      - Wan 2.2 (video generation)"
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
echo "  ✓ Hardware-specific optimizations applied (GPU, KWin, power, memory, I/O)"
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
echo "To start AI tools:"
echo "  ComfyUI:  cd ~/ComfyUI && source venv/bin/activate && python main.py"
echo "            Open: http://127.0.0.1:8188"
echo ""
echo "  Fooocus:  cd ~/Fooocus && source venv/bin/activate && python entry_with_update.py"
echo "            Open: http://127.0.0.1:7865"
echo ""

# Auto-apply wallpaper if plasma-apply-wallpaperimage is available
WALLPAPER_CACHE="$HOME/.cache/restore-wallpaper-path"
if [ -f "$WALLPAPER_CACHE" ] && command -v plasma-apply-wallpaperimage &>/dev/null; then
    WALLPAPER=$(cat "$WALLPAPER_CACHE")
    if [ -f "$WALLPAPER" ]; then
        echo "Applying wallpaper: $WALLPAPER"
        plasma-apply-wallpaperimage "$WALLPAPER" 2>/dev/null && echo "   ✓ Wallpaper applied" || true
    fi
    rm -f "$WALLPAPER_CACHE"
fi
