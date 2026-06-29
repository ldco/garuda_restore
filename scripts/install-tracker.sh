#!/bin/bash
# ============================================================================
# INSTALL TRACKER - Captures all installed software from all package managers
# ============================================================================
# Run periodically (via timer) or manually to snapshot current installed state.
# The backup script uses this snapshot for restore.
# ============================================================================

set -e

TRACKER_DIR="$HOME/.local/share/garuda-backup/installed"
mkdir -p "$TRACKER_DIR"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Scanning installed software..."

# Known-unavailable packages (removed from AUR, no longer installable)
AUR_EXCLUDE="nocowboy ypn-client"

# ============================================================================
# 1. PACMAN - Official packages (explicitly installed)
# ============================================================================
pacman -Qe --quiet > "$TRACKER_DIR/pacman-explicit.txt" 2>/dev/null || true
pacman -Qe > "$TRACKER_DIR/pacman-explicit-versions.txt" 2>/dev/null || true

# Filter out known-unavailable packages from pacman lists
for pkg in $AUR_EXCLUDE; do
    sed -i "/^${pkg}\b/d" "$TRACKER_DIR/pacman-explicit.txt" 2>/dev/null || true
    sed -i "/^${pkg}\b/d" "$TRACKER_DIR/pacman-explicit-versions.txt" 2>/dev/null || true
done

echo "✓ Pacman: $(wc -l < "$TRACKER_DIR/pacman-explicit.txt") packages"

# ============================================================================
# 2. AUR - Packages from AUR (paru/yay)
# ============================================================================
pacman -Qm --quiet > "$TRACKER_DIR/aur-packages.txt" 2>/dev/null || true
pacman -Qm > "$TRACKER_DIR/aur-packages-versions.txt" 2>/dev/null || true

# Filter out known-unavailable AUR packages
for pkg in $AUR_EXCLUDE; do
    sed -i "/^${pkg}\b/d" "$TRACKER_DIR/aur-packages.txt" 2>/dev/null || true
    sed -i "/^${pkg}\b/d" "$TRACKER_DIR/aur-packages-versions.txt" 2>/dev/null || true
done

echo "✓ AUR: $(wc -l < "$TRACKER_DIR/aur-packages.txt") packages"

# ============================================================================
# 3. NPM - Global Node packages
# ============================================================================
if command -v npm &>/dev/null; then
    npm list -g --depth=0 --json > "$TRACKER_DIR/npm-global.json" 2>/dev/null || true
    npm list -g --depth=0 2>/dev/null | tail -n +2 | sed 's/├── //g; s/└── //g' > "$TRACKER_DIR/npm-global.txt" || true
    echo "✓ NPM global: $(wc -l < "$TRACKER_DIR/npm-global.txt") packages"
fi

# ============================================================================
# 4. PIP - Global Python packages (user installed)
# ============================================================================
if command -v pip &>/dev/null; then
    pip list --user --format=json > "$TRACKER_DIR/pip-user.json" 2>/dev/null || true
    pip list --user --format=freeze > "$TRACKER_DIR/pip-user.txt" 2>/dev/null || true
    echo "✓ PIP user: $(wc -l < "$TRACKER_DIR/pip-user.txt") packages"
fi

# ============================================================================
# 5. PIPX - Isolated Python apps
# ============================================================================
if command -v pipx &>/dev/null; then
    pipx list --json > "$TRACKER_DIR/pipx.json" 2>/dev/null || true
    pipx list --short > "$TRACKER_DIR/pipx.txt" 2>/dev/null || true
    echo "✓ Pipx: $(wc -l < "$TRACKER_DIR/pipx.txt") apps"
fi

# ============================================================================
# 6. CARGO - Rust packages
# ============================================================================
if command -v cargo &>/dev/null && [ -d "$HOME/.cargo/bin" ]; then
    ls "$HOME/.cargo/bin" > "$TRACKER_DIR/cargo-bins.txt" 2>/dev/null || true
    echo "✓ Cargo: $(wc -l < "$TRACKER_DIR/cargo-bins.txt") binaries"
fi

# ============================================================================
# 7. FLATPAK - Flatpak apps
# ============================================================================
if command -v flatpak &>/dev/null; then
    flatpak list --app --columns=application > "$TRACKER_DIR/flatpak.txt" 2>/dev/null || true
    echo "✓ Flatpak: $(wc -l < "$TRACKER_DIR/flatpak.txt") apps"
fi

# ============================================================================
# 8. SNAP - Snap packages
# ============================================================================
if command -v snap &>/dev/null; then
    snap list 2>/dev/null | tail -n +2 | awk '{print $1}' > "$TRACKER_DIR/snap.txt" || true
    echo "✓ Snap: $(wc -l < "$TRACKER_DIR/snap.txt") packages"
fi

# ============================================================================
# 9. GIT CLONES - Repositories in home directory
# ============================================================================
echo "# Git repositories in home directory" > "$TRACKER_DIR/git-repos.txt"
echo "# Format: directory|remote_url" >> "$TRACKER_DIR/git-repos.txt"
find "$HOME" -maxdepth 3 -type d -name ".git" 2>/dev/null | while read gitdir; do
    REPO_DIR=$(dirname "$gitdir")
    REPO_NAME=$(basename "$REPO_DIR")
    REMOTE_URL=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "no-remote")
    # Skip common non-app repos
    [[ "$REPO_DIR" == *"/.cache/"* ]] && continue
    [[ "$REPO_DIR" == *"/.local/share/"* ]] && continue
    [[ "$REPO_NAME" == "garuda-restore" ]] && continue
    echo "$REPO_DIR|$REMOTE_URL" >> "$TRACKER_DIR/git-repos.txt"
done
GIT_COUNT=$(grep -v "^#" "$TRACKER_DIR/git-repos.txt" | wc -l)
echo "✓ Git repos: $GIT_COUNT repositories"

# ============================================================================
# 10. SYSTEMD USER SERVICES - Enabled services
# ============================================================================
systemctl --user list-unit-files --state=enabled --no-pager 2>/dev/null | \
    grep enabled | awk '{print $1}' > "$TRACKER_DIR/systemd-user-enabled.txt" || true
echo "✓ Systemd user: $(wc -l < "$TRACKER_DIR/systemd-user-enabled.txt") services"

# ============================================================================
# 11. DESKTOP APPS - Custom .desktop files
# ============================================================================
if [ -d "$HOME/.local/share/applications" ]; then
    ls "$HOME/.local/share/applications/"*.desktop 2>/dev/null | \
        xargs -I {} basename {} > "$TRACKER_DIR/desktop-apps.txt" || true
    echo "✓ Desktop apps: $(wc -l < "$TRACKER_DIR/desktop-apps.txt") launchers"
fi

# ============================================================================
# 12. GNOME EXTENSIONS / KDE WIDGETS (if applicable)
# ============================================================================
if [ -d "$HOME/.local/share/plasma/plasmoids" ]; then
    ls "$HOME/.local/share/plasma/plasmoids" > "$TRACKER_DIR/kde-widgets.txt" 2>/dev/null || true
    echo "✓ KDE widgets: $(wc -l < "$TRACKER_DIR/kde-widgets.txt") widgets"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "Installed software snapshot saved to: $TRACKER_DIR"
echo "Last updated: $(date)" > "$TRACKER_DIR/last-updated.txt"

# Create a summary file
cat > "$TRACKER_DIR/SUMMARY.txt" << EOF
# Installed Software Summary
# Generated: $(date)
# ============================================================================

Pacman (explicit):  $(wc -l < "$TRACKER_DIR/pacman-explicit.txt") packages
AUR packages:       $(wc -l < "$TRACKER_DIR/aur-packages.txt") packages
NPM global:         $([ -f "$TRACKER_DIR/npm-global.txt" ] && wc -l < "$TRACKER_DIR/npm-global.txt" || echo "0") packages
PIP user:           $([ -f "$TRACKER_DIR/pip-user.txt" ] && wc -l < "$TRACKER_DIR/pip-user.txt" || echo "0") packages
Cargo binaries:     $([ -f "$TRACKER_DIR/cargo-bins.txt" ] && wc -l < "$TRACKER_DIR/cargo-bins.txt" || echo "0") binaries
Flatpak:            $([ -f "$TRACKER_DIR/flatpak.txt" ] && wc -l < "$TRACKER_DIR/flatpak.txt" || echo "0") apps
Git repositories:   $GIT_COUNT repos
Desktop launchers:  $([ -f "$TRACKER_DIR/desktop-apps.txt" ] && wc -l < "$TRACKER_DIR/desktop-apps.txt" || echo "0") apps

EOF

echo "Done!"
