#!/bin/bash
# ============================================================================
# Remove Duplicate System Titlebars on KDE Plasma (Hardened)
# ============================================================================
# This script removes KDE decorations from Electron/GTK apps that have their
# own titlebars (CSD). Result: Only the app's colored titlebar shows.
#
# CHANGES FROM ORIGINAL:
# - Creates timestamped backup before any write
# - Merges rules into existing kwinrulesrc (doesn't overwrite)
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

echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}      Remove Duplicate System Titlebars${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Generate timestamp for backups
TIMESTAMP=$(date +%Y%m%d%H%M%S)

# ============================================================================
# 1. VS Code - Use app's titlebar (disable system decoration)
# ============================================================================
echo -e "${CYAN}[1/6] Configuring VS Code...${NC}"
mkdir -p ~/.config/Code/User

# Backup existing settings.json if it exists
if [ -f ~/.config/Code/User/settings.json ]; then
    cp ~/.config/Code/User/settings.json "~/.config/Code/User/settings.json.backup.$TIMESTAMP"
    echo "   ✓ Backed up existing settings.json"
fi

# Merge settings (preserve existing settings, override titlebar-related)
if [ -f ~/.config/Code/User/settings.json ]; then
    # Use jq if available, otherwise use simple approach
    if command -v jq &>/dev/null; then
        # Merge with existing settings
        jq '. + {
            "window.titleBarStyle": "inset",
            "window.customTitleBarVisibility": "auto",
            "window.menuBarVisibility": "toggle"
        }' ~/.config/Code/User/settings.json > /tmp/vscode-settings.tmp.$$
        mv /tmp/vscode-settings.tmp.$$ ~/.config/Code/User/settings.json
    else
        # Simple approach: add/replace lines
        awk '
        BEGIN { found_title=0; found_custom=0; found_menu=0 }
        /"window.titleBarStyle"/ { print "    \"window.titleBarStyle\": \"inset\","; found_title=1; next }
        /"window.customTitleBarVisibility"/ { print "    \"window.customTitleBarVisibility\": \"auto\","; found_custom=1; next }
        /"window.menuBarVisibility"/ { print "    \"window.menuBarVisibility\": \"toggle\""; found_menu=1; next }
        { print }
        END {
            if (!found_title) print "    \"window.titleBarStyle\": \"inset\","
            if (!found_custom) print "    \"window.customTitleBarVisibility\": \"auto\","
            if (!found_menu) print "    \"window.menuBarVisibility\": \"toggle\""
        }
        ' ~/.config/Code/User/settings.json > /tmp/vscode-settings.tmp.$$
        mv /tmp/vscode-settings.tmp.$$ ~/.config/Code/User/settings.json
    fi
    echo "   ✓ Merged VS Code settings"
else
    # Create new settings.json
    cat > ~/.config/Code/User/settings.json << 'EOF'
{
    "window.titleBarStyle": "inset",
    "window.customTitleBarVisibility": "auto",
    "window.menuBarVisibility": "toggle"
}
EOF
    echo "   ✓ Created VS Code settings"
fi

# ============================================================================
# 2. GTK CSD - Force GTK apps to use their own decorations
# ============================================================================
echo -e "${CYAN}[2/6] Configuring GTK apps (Inkscape, GIMP, etc.)...${NC}"
mkdir -p ~/.config/environment.d

# Backup existing gtk-csd.conf if it exists
if [ -f ~/.config/environment.d/gtk-csd.conf ]; then
    cp ~/.config/environment.d/gtk-csd.conf "~/.config/environment.d/gtk-csd.conf.backup.$TIMESTAMP"
    echo "   ✓ Backed up existing gtk-csd.conf"
fi

cat > ~/.config/environment.d/gtk-csd.conf << 'EOF'
# Force GTK apps to use Client-Side Decorations (CSD)
# This makes GTK apps draw their own titlebars instead of using KDE decorations
GTK_CSD=1
EOF
echo "   ✓ GTK CSD configured"

# ============================================================================
# 3. KWin rules - Merge with existing rules (don't overwrite)
# ============================================================================
echo -e "${CYAN}[3/6] Configuring KWin rules...${NC}"

KWIN_RULES="$HOME/.config/kwinrulesrc"
BACKUP_RULES="$HOME/.config/kwinrulesrc.backup.$TIMESTAMP"

# Backup existing kwinrulesrc if it exists
if [ -f "$KWIN_RULES" ]; then
    cp "$KWIN_RULES" "$BACKUP_RULES"
    echo "   ✓ Backed up existing kwinrulesrc"
    
    # Read existing count and rules
    EXISTING_COUNT=$(grep -E '^count=' "$KWIN_RULES" 2>/dev/null | cut -d'=' -f2 || echo "0")
    EXISTING_RULES=$(grep -E '^rules=' "$KWIN_RULES" 2>/dev/null | cut -d'=' -f2 || echo "")
    
    # Our new rule UUIDs
    NEW_UUIDS="{11111111-1111-1111-1111-111111111111};{22222222-2222-2222-2222-222222222222};{33333333-3333-3333-3333-333333333333};{44444444-4444-4444-4444-444444444444};{55555555-5555-5555-5555-555555555555}"
    
    # Calculate new count (existing + 5 new rules)
    if [ -n "$EXISTING_COUNT" ] && [ "$EXISTING_COUNT" -gt 0 ] 2>/dev/null; then
        NEW_COUNT=$((EXISTING_COUNT + 5))
    else
        NEW_COUNT=5
    fi
    
    # Merge rules (existing + new)
    if [ -n "$EXISTING_RULES" ]; then
        NEW_RULES="${EXISTING_RULES};${NEW_UUIDS}"
    else
        NEW_RULES="$NEW_UUIDS"
    fi
    
    # Remove old rule sections for our UUIDs if they exist (to avoid duplicates)
    grep -v -E '^\[{11111111-|^\[{22222222-|^\[{33333333-|^\[{44444444-|^\[{55555555-' "$KWIN_RULES" > /tmp/kwinrules.tmp.$$ 2>/dev/null || true
    
    # Update count and rules
    sed -i "s/^count=.*/count=$NEW_COUNT/" /tmp/kwinrules.tmp.$$ 2>/dev/null || echo "count=$NEW_COUNT" >> /tmp/kwinrules.tmp.$$
    sed -i "s/^rules=.*/rules=$NEW_RULES/" /tmp/kwinrules.tmp.$$ 2>/dev/null || echo "rules=$NEW_RULES" >> /tmp/kwinrules.tmp.$$
    
    # Append new rule sections
    cat >> /tmp/kwinrules.tmp.$$ << 'EOF'

[{11111111-1111-1111-1111-111111111111}]
Description=VS Code - Remove System Titlebar (use app CSD)
types=1
wmclass=Code
wmclassmatch=1
noborder=true
noborderrule=2

[{22222222-2222-2222-2222-222222222222}]
Description=Chrome - Remove System Titlebar (use app CSD)
types=1
wmclass=google-chrome
wmclassmatch=1
noborder=true
noborderrule=2

[{33333333-3333-3333-3333-333333333333}]
Description=Brave - Remove System Titlebar (use app CSD)
types=1
wmclass=brave-browser
wmclassmatch=1
noborder=true
noborderrule=2

[{44444444-4444-4444-4444-444444444444}]
Description=Electron Apps - Remove System Titlebar (use app CSD)
types=1
wmclass=electron
wmclassmatch=2
noborder=true
noborderrule=2

[{55555555-5555-5555-5555-555555555555}]
Description=Discord/Slack - Remove System Titlebar (use app CSD)
types=1
wmclass=discord|slack
wmclassmatch=2
noborder=true
noborderrule=2
EOF
    
    mv /tmp/kwinrules.tmp.$$ "$KWIN_RULES"
    echo "   ✓ Merged KWin rules (total: $NEW_COUNT rules)"
else
    # Create new kwinrulesrc
    cat > "$KWIN_RULES" << 'EOF'
[General]
count=5
rules={11111111-1111-1111-1111-111111111111};{22222222-2222-2222-2222-222222222222};{33333333-3333-3333-3333-333333333333};{44444444-4444-4444-4444-444444444444};{55555555-5555-5555-5555-555555555555}

[{11111111-1111-1111-1111-111111111111}]
Description=VS Code - Remove System Titlebar (use app CSD)
types=1
wmclass=Code
wmclassmatch=1
noborder=true
noborderrule=2

[{22222222-2222-2222-2222-222222222222}]
Description=Chrome - Remove System Titlebar (use app CSD)
types=1
wmclass=google-chrome
wmclassmatch=1
noborder=true
noborderrule=2

[{33333333-3333-3333-3333-333333333333}]
Description=Brave - Remove System Titlebar (use app CSD)
types=1
wmclass=brave-browser
wmclassmatch=1
noborder=true
noborderrule=2

[{44444444-4444-4444-4444-444444444444}]
Description=Electron Apps - Remove System Titlebar (use app CSD)
types=1
wmclass=electron
wmclassmatch=2
noborder=true
noborderrule=2

[{55555555-5555-5555-5555-555555555555}]
Description=Discord/Slack - Remove System Titlebar (use app CSD)
types=1
wmclass=discord|slack
wmclassmatch=2
noborder=true
noborderrule=2
EOF
    echo "   ✓ Created KWin rules"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Done!${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "To apply changes:"
echo "  1. ${YELLOW}LOG OUT and log back in${NC} (required for GTK_CSD to take effect)"
echo "  2. KWin rules apply immediately to new windows"
echo "  3. Apps will now show ONLY their colored titlebar"
echo ""
echo -e "${CYAN}Backup created:${NC}"
echo "  - ~/.config/Code/User/settings.json.backup.$TIMESTAMP"
echo "  - ~/.config/environment.d/gtk-csd.conf.backup.$TIMESTAMP"
[ -f "$BACKUP_RULES" ] && echo "  - $BACKUP_RULES"
echo ""
echo -e "${YELLOW}To rollback:${NC}"
echo "  ./scripts/restore-system-titlebars.sh"
echo ""
