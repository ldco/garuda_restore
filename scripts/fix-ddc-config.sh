#!/bin/bash
# ============================================================================
# Fix KWin Output Config - Disable DDC/CI on all monitors
# ============================================================================
# The frozen config requires allowDdcCi=false on ALL monitors to prevent
# NVIDIA I2C transfer errors and screen flickering.
#
# This script ensures all monitors have DDC/CI disabled.
# ============================================================================

set -e

KWIN_CONFIG="$HOME/.config/kwinoutputconfig.json"

echo "═══════════════════════════════════════════════════════════"
echo "        KWin Output Config - DDC/CI Fix"
echo "═══════════════════════════════════════════════════════════"
echo ""

if [ ! -f "$KWIN_CONFIG" ]; then
    echo "No kwinoutputconfig.json found at $KWIN_CONFIG"
    echo "KWin will generate defaults on next login."
    echo ""
    echo "To disable DDC/CI manually:"
    echo "  System Settings → Display & Monitor → Display Configuration"
    echo "  → Click each monitor → Uncheck 'Control hardware brightness with DDC/CI'"
    exit 0
fi

echo "Current config:"
echo "───────────────────────────────────────────────────────────"
cat "$KWIN_CONFIG" | grep -A2 -B2 "allowDdcCi" || echo "No allowDdcCi settings found"
echo ""

# Check if any monitors have allowDdcCi set to true
if grep -q '"allowDdcCi": *true' "$KWIN_CONFIG" 2>/dev/null; then
    echo "⚠ Found monitors with allowDdcCi=true (can cause flickering)"
    echo ""
    echo "Fixing: Setting allowDdcCi=false on ALL monitors..."
    echo ""
    
    # Use sed to replace all instances of "allowDdcCi": true with false
    # This handles both spaced and non-spaced variants
    if sed -i 's/"allowDdcCi": *true/"allowDdcCi": false/g' "$KWIN_CONFIG"; then
        echo "✓ Fixed allowDdcCi settings"
    else
        echo "⚠ Could not automatically fix config"
        echo "  Please fix manually via System Settings GUI"
        exit 1
    fi
    
    echo ""
    echo "Updated config:"
    echo "───────────────────────────────────────────────────────────"
    cat "$KWIN_CONFIG" | grep -A2 -B2 "allowDdcCi" || echo "No allowDdcCi settings found"
    echo ""
    
    echo "═══════════════════════════════════════════════════════════"
    echo "  IMPORTANT: Logout and login (or reboot) for changes to"
    echo "  take effect!"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
else
    echo "✓ All monitors already have allowDdcCi=false"
    echo ""
    echo "Config is correct - no changes needed."
fi

echo ""
