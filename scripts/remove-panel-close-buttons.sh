#!/bin/bash
# ============================================================================
# Remove Close Button Tray from KDE Plasma Panel
# ============================================================================
# This removes unwanted window control buttons from the top-left panel area
# These are typically from "Window List" or "Window Buttons" applets
# ============================================================================

set -e

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║         Remove Panel Close Button Tray (KDE Plasma)                  ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Check if plasma config exists
if [ ! -f "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" ]; then
    echo "ERROR: Plasma config not found. Is KDE running?"
    exit 1
fi

BACKUP_FILE="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc.backup.$(date +%Y%m%d%H%M%S)"

echo "[1/4] Backing up current plasma config..."
cp "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" "$BACKUP_FILE"
echo "      Backup saved to: $BACKUP_FILE"

echo ""
echo "[2/4] Identifying panel applets..."

# Show current applets in the top panel (containment 2 is usually the desktop panel)
echo ""
echo "Current panel applets:"
grep -A5 "\[Containment\|^\[Applet" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" | head -40

echo ""
echo "[3/4] Looking for window button/window list applets..."

# Find applets that might be showing window controls
WINDOW_APPLETS=$(grep -n "org.kde.plasma.windowlist\|org.kde.plasma.taskmanager\|window-buttons\|WindowList" "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc" 2>/dev/null || true)

if [ -n "$WINDOW_APPLETS" ]; then
    echo ""
    echo "Found potential window button applets:"
    echo "$WINDOW_APPLETS"
    echo ""
    echo "⚠️  MANUAL ACTION REQUIRED:"
    echo ""
    echo "These applets cannot be safely removed automatically."
    echo "Please do the following:"
    echo ""
    echo "1. Right-click on the panel (top bar)"
    echo "2. Click 'Enter Edit Mode'"
    echo "3. Find the widget showing close buttons (usually in top-left)"
    echo "4. Click the 'X' or 'Remove' button on that widget"
    echo "5. Click 'Exit Edit Mode'"
    echo ""
else
    echo "No obvious window button applets found in config."
    echo ""
    echo "The close buttons might be from:"
    echo "  • System Tray showing 'Window Manager' items"
    echo "  • A custom panel layout"
    echo ""
fi

echo ""
echo "[4/4] Restarting Plasma shell..."

# Try graceful restart via D-Bus
if qdbus6 org.kde.plasmashell /PlasmaShell org.kde.plasmashell.evaluateScript "restart()" 2>/dev/null; then
    echo "      Plasma restarted via D-Bus"
else
    # Fallback
    echo "      D-Bus restart failed, using fallback..."
    (killall plasmashell && kstart6 plasmashell &) 2>/dev/null || true
    sleep 3
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Done! If close buttons persist, use Edit Mode to remove the widget ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "To restore backup if needed:"
echo "  cp $BACKUP_FILE ~/.config/plasma-org.kde.plasma.desktop-appletsrc"
echo "  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.plasmashell.evaluateScript restart()"
echo ""
