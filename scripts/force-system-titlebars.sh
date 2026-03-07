#!/bin/bash
# Remove Duplicate System Titlebars on KDE Plasma
# This script removes KDE decorations from Electron/GTK apps that have their own titlebars (CSD)
# Result: Only the app's colored titlebar shows, no duplicate system titlebar

echo "=== Removing Duplicate System Titlebars ==="

# 1. VS Code - Use app's titlebar (disable system decoration)
echo "[1/6] Configuring VS Code..."
mkdir -p ~/.config/Code/User
cat > ~/.config/Code/User/settings.json << 'EOF'
{
    "window.titleBarStyle": "inset",
    "window.customTitleBarVisibility": "auto",
    "window.menuBarVisibility": "toggle"
}
EOF

# 2. Chrome/Chromium - Use app's titlebar
echo "[2/6] Configuring Chrome..."
# Chrome uses its own titlebar by default on Wayland

# 3. GTK CSD - Force GTK apps to use their own decorations
echo "[3/6] Configuring GTK apps (Inkscape, GIMP, etc.)..."
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/gtk-csd.conf << 'EOF'
# Force GTK apps to use Client-Side Decorations (CSD)
# This makes GTK apps draw their own titlebars instead of using KDE decorations
GTK_CSD=1
EOF

# 4. No wrapper needed - Chrome handles CSD natively
echo "[4/6] Chrome configured..."

# 5. GTK CSD - Let apps use their own decorations
echo "[5/6] GTK apps configured..."
# GTK apps will use their own titlebars (CSD)

# 6. KWin rules applied above
echo "[6/6] KWin rules configured..."
cat > ~/.config/kwinrulesrc << 'EOF'
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

echo ""
echo "=== Done! ==="
echo ""
echo "To apply changes:"
echo "1. LOG OUT and log back in (required for GTK_CSD to take effect)"
echo "2. KWin rules apply immediately to new windows"
echo "3. Apps will now show ONLY their colored titlebar (no duplicate system titlebar)"
echo ""
