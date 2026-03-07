#!/bin/bash
# ============================================================================
# Restore System Titlebars on KDE Plasma (Hardened)
# ============================================================================
# This script RESTORES normal window decorations (titlebars with close buttons)
# to apps that previously had them removed by force-system-titlebars.sh
#
# CHANGES FROM ORIGINAL:
# - Creates timestamped backup before any write
# - Merges rules (removes only our specific rules, preserves others)
# - Safer KWin restart (doesn't quit first, checks process alive)
# - Prints explicit rollback command on exit
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      Restore System Titlebars (KDE Plasma)                ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Generate timestamp for backups
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# ============================================================================
# 1. VS Code - Use system titlebar (disable CSD)
# ============================================================================
echo -e "${CYAN}[1/5] Configuring VS Code...${NC}"
mkdir -p ~/.config/Code/User

# Backup existing settings.json if it exists
if [ -f ~/.config/Code/User/settings.json ]; then
    cp ~/.config/Code/User/settings.json "~/.config/Code/User/settings.json.backup.$TIMESTAMP"
    echo "   ✓ Backed up existing settings.json"
fi

# Merge settings (preserve existing settings, override titlebar-related)
if [ -f ~/.config/Code/User/settings.json ]; then
    if command -v jq &>/dev/null; then
        jq '. + {
            "window.titleBarStyle": "native",
            "window.menuBarVisibility": "default"
        }' ~/.config/Code/User/settings.json > /tmp/vscode-settings.tmp.$$
        mv /tmp/vscode-settings.tmp.$$ ~/.config/Code/User/settings.json
    else
        awk '
        BEGIN { found_title=0; found_menu=0 }
        /"window.titleBarStyle"/ { print "    \"window.titleBarStyle\": \"native\","; found_title=1; next }
        /"window.menuBarVisibility"/ { print "    \"window.menuBarVisibility\": \"default\""; found_menu=1; next }
        { print }
        END {
            if (!found_title) print "    \"window.titleBarStyle\": \"native\","
            if (!found_menu) print "    \"window.menuBarVisibility\": \"default\""
        }
        ' ~/.config/Code/User/settings.json > /tmp/vscode-settings.tmp.$$
        mv /tmp/vscode-settings.tmp.$$ ~/.config/Code/User/settings.json
    fi
    echo "   ✓ VS Code will use system titlebar"
else
    cat > ~/.config/Code/User/settings.json << 'EOF'
{
    "window.titleBarStyle": "native",
    "window.menuBarVisibility": "default"
}
EOF
    echo "   ✓ VS Code configured"
fi

# ============================================================================
# 2. Clear KWin border rules (merge - remove only our rules)
# ============================================================================
echo -e "${CYAN}[2/5] Removing KWin no-border rules...${NC}"

KWIN_RULES="$HOME/.config/kwinrulesrc"
BACKUP_RULES="$HOME/.config/kwinrulesrc.backup.$TIMESTAMP"

if [ -f "$KWIN_RULES" ]; then
    cp "$KWIN_RULES" "$BACKUP_RULES"
    echo "   ✓ Backed up existing kwinrulesrc"
    
    # Read existing count and rules
    EXISTING_COUNT=$(grep -E '^count=' "$KWIN_RULES" 2>/dev/null | cut -d'=' -f2 || echo "0")
    EXISTING_RULES=$(grep -E '^rules=' "$KWIN_RULES" 2>/dev/null | cut -d'=' -f2 || echo "")
    
    # Our rule UUIDs to remove
    OUR_UUIDS="11111111-1111-1111-1111-111111111111|22222222-2222-2222-2222-222222222222|33333333-3333-3333-3333-333333333333|44444444-4444-4444-4444-444444444444|55555555-5555-5555-5555-555555555555"
    
    # Remove our rule sections
    grep -v -E "^\[({)?($OUR_UUIDS)" "$KWIN_RULES" > /tmp/kwinrules.tmp.$$ 2>/dev/null || true
    
    # Count remaining rules (exclude General section and empty lines)
    REMAINING_RULES=$(grep -c '^\[{' /tmp/kwinrules.tmp.$$ 2>/dev/null || echo "0")
    
    # Extract remaining rule UUIDs
    REMAINING_UUIDS=$(grep -E '^\[{' /tmp/kwinrules.tmp.$$ 2>/dev/null | sed 's/^\[//;s/\]$//' | tr '\n' ';' | sed 's/;$//' || echo "")
    
    # Update count and rules
    sed -i "s/^count=.*/count=$REMAINING_RULES/" /tmp/kwinrules.tmp.$$ 2>/dev/null || echo "count=$REMAINING_RULES" >> /tmp/kwinrules.tmp.$$
    sed -i "s/^rules=.*/rules=$REMAINING_UUIDS/" /tmp/kwinrules.tmp.$$ 2>/dev/null || echo "rules=$REMAINING_UUIDS" >> /tmp/kwinrules.tmp.$$
    
    mv /tmp/kwinrules.tmp.$$ "$KWIN_RULES"
    echo "   ✓ Removed no-border rules (remaining: $REMAINING_RULES rules)"
else
    echo "   ⊘ No existing kwinrulesrc found"
fi

# ============================================================================
# 3. Reset GTK decorations
# ============================================================================
echo -e "${CYAN}[3/5] Configuring GTK apps...${NC}"

if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.wm.preferences button-layout 'close,minimize,maximize:' 2>/dev/null && \
        echo "   ✓ GTK button layout set to left (KDE style)" || \
        echo "   ⊘ gsettings not available"
else
    echo "   ⊘ gsettings not available - GTK apps will use defaults"
fi

# ============================================================================
# 4. Force KWin to re-read rules
# ============================================================================
echo -e "${CYAN}[4/5] Applying KWin configuration...${NC}"

if command -v kwriteconfig6 &>/dev/null; then
    kwriteconfig6 --file kwinrulesrc --group "General" --key "count" "$(grep -E '^count=' "$KWIN_RULES" 2>/dev/null | cut -d'=' -f2 || echo "0")" 2>/dev/null || true
    kwriteconfig6 --file kwinrulesrc --group "General" --key "rules" "$(grep -E '^rules=' "$KWIN_RULES" 2>/dev/null | cut -d'=' -f2 || echo "")" 2>/dev/null || true
    echo "   ✓ KWin configuration updated"
else
    echo "   ⊘ kwriteconfig6 not available"
fi

# ============================================================================
# 5. Restart KWin (safer - don't quit first)
# ============================================================================
echo -e "${CYAN}[5/5] Restarting KWin...${NC}"

# Get current KWin PID before restart
OLD_KWIN_PID=$(pgrep -x kwin_wayland 2>/dev/null || pgrep -x kwin 2>/dev/null || echo "")

# Start KWin replacement (don't quit first - safer)
kwin6 --replace &
KWIN_START_PID=$!

echo "   Waiting for KWin to restart..."

# Wait for new KWin to be alive (up to 10 seconds)
for i in {1..20}; do
    sleep 0.5
    NEW_KWIN_PID=$(pgrep -x kwin_wayland 2>/dev/null || pgrep -x kwin 2>/dev/null || echo "")
    if [ -n "$NEW_KWIN_PID" ] && [ "$NEW_KWIN_PID" != "$OLD_KWIN_PID" ]; then
        echo "   ✓ KWin restarted (PID: $NEW_KWIN_PID)"
        break
    fi
    if [ $i -eq 20 ]; then
        echo -e "   ${YELLOW}⚠ KWin restart may have failed${NC}"
        echo "   Manual recovery: kwin6 --replace &"
    fi
done

echo ""
echo -e "${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║  Done! Apps will now show normal KDE titlebars            ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart any open applications to see the new titlebars"
echo "  2. You can now remove the panel close button tray:"
echo "     • Right-click panel → Enter Edit Mode"
echo "     • Remove the 'Window List' or window buttons widget"
echo "     • Exit Edit Mode"
echo ""
echo -e "${CYAN}Backup created:${NC}"
[ -f "$BACKUP_RULES" ] && echo "  - $BACKUP_RULES"
[ -f ~/.config/Code/User/settings.json.backup.$TIMESTAMP ] && echo "  - ~/.config/Code/User/settings.json.backup.$TIMESTAMP"
echo ""
echo -e "${YELLOW}To reverse (go back to CSD):${NC}"
echo "  ./scripts/force-system-titlebars.sh"
echo ""
