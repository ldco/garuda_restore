#!/bin/bash
# ============================================================================
# APPLY OPAQUE KDE THEME — Remove all transparency, keep window buttons
# ============================================================================
# Sets Sweet-Dark aurorae (opaque) with IAX buttons + disables all blur.
# Idempotent — safe to re-run.
# ============================================================================

set -e

echo "=== Opaque KDE Theme ==="

# 1. Window decorations: Sweet-Dark aurorae (opaque, NOT transparent variant)
echo "[1/4] Setting window decorations..."
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Sweet-Dark
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight IAX
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize Normal
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSizeAuto false
echo "  ✓ Sweet-Dark + IAX buttons"

# 2. Disable all blur and transparency effects
echo "[2/4] Disabling blur/transparency..."
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key better_blur_dxEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key forceblurEnabled false
echo "  ✓ Blur disabled"

# 3. Disable transparency-specific decorations
echo "[3/4] Disabling transparent decorations..."
kwriteconfig6 --file kwinrc --group "Effect-better-blur-dx" --key BlurDecorations false
kwriteconfig6 --file kwinrc --group "Effect-better-blur-dx" --key BlurDocks false
kwriteconfig6 --file kwinrc --group "Effect-better-blur-dx" --key BlurMenus false
kwriteconfig6 --file kwinrc --group "Effect-better-blur-dx" --key BlurNonMatching false
echo "  ✓ Transparent decorations disabled"

# 4. Reload KWin
echo "[4/4] Applying..."
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
echo "  ✓ Done"
echo ""
echo "Window buttons: Close (X), Maximize (A), Minimize (I)"
echo "Theme: Sweet-Dark aurorae (opaque)"
echo "Blur: OFF"
echo ""
echo "If buttons still missing: System Settings → Window Decorations → edit Sweet-Dark → Buttons tab → drag IAX to titlebar"
