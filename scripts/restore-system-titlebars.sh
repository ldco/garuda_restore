#!/bin/bash
# ============================================================================
# Restore System Titlebars on KDE Plasma
# ============================================================================
# This script RESTORES normal window decorations (titlebars with close buttons)
# to apps that previously had them removed by force-system-titlebars.sh
#
# Result: Apps show normal KDE titlebars with close/minimize/maximize buttons
#         Panel window buttons become optional (can be removed)
# ============================================================================

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║          Restore System Titlebars (KDE Plasma)                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# 1. VS Code - Use system titlebar (disable CSD)
echo "[1/5] Configuring VS Code..."
mkdir -p ~/.config/Code/User
cat > ~/.config/Code/User/settings.json << 'EOF'
{
    "window.titleBarStyle": "native",
    "window.menuBarVisibility": "default"
}
EOF
echo "      ✓ VS Code will use system titlebar"

# 2. Clear KWin border rules
echo "[2/5] Removing KWin no-border rules..."
cat > ~/.config/kwinrulesrc << 'EOF'
[General]
count=0
rules=
EOF
echo "      ✓ KWin rules cleared"

# 3. Reset GTK decorations (ensure GTK apps use system titlebars)
echo "[3/5] Configuring GTK apps..."
# Empty value means "use system decorations"
gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null || {
    echo "      (gsettings not available - GTK apps will use defaults)"
}
echo "      ✓ GTK button layout set to left (KDE style)"

# 4. Force KWin to re-read rules
echo "[4/5] Applying KWin configuration..."
kwriteconfig6 --file kwinrulesrc --group "General" --key "count" "0" 2>/dev/null || true
kwriteconfig6 --file kwinrulesrc --group "General" --key "rules" "" 2>/dev/null || true

# 5. Restart KWin to apply changes
echo "[5/5] Restarting KWin..."
kquitapp6 kwin && kwin6 --replace &
sleep 2

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║  Done! Apps will now show normal KDE titlebars                       ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo "1. Restart any open applications to see the new titlebars"
echo "2. You can now remove the panel close button tray:"
echo "   • Right-click panel → Enter Edit Mode"
echo "   • Remove the 'Window List' or window buttons widget"
echo "   • Exit Edit Mode"
echo ""
echo "To reverse this (go back to CSD), run:"
echo "  ./scripts/force-system-titlebars.sh"
echo ""
