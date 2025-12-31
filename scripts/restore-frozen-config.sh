#!/bin/bash
set -e

# Restore Frozen Configuration from 2024-12-30
# This restores the known-good system state

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/../configs/frozen-2024-12-30"

echo "========================================"
echo "  Restore Frozen Config (2024-12-30)"
echo "========================================"
echo ""

if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo "[1/7] Restoring /etc/environment..."
sudo cp "$BACKUP_DIR/etc-environment" /etc/environment
sudo chown root:root /etc/environment
echo "   Done"

echo "[2/7] Restoring kwinrc..."
cp "$BACKUP_DIR/kwinrc" ~/.config/kwinrc
echo "   Done"

echo "[3/7] Restoring kwinoutputconfig.json..."
cp "$BACKUP_DIR/kwinoutputconfig.json" ~/.config/kwinoutputconfig.json
echo "   Done"

echo "[4/7] Restoring kwinrulesrc..."
cp "$BACKUP_DIR/kwinrulesrc" ~/.config/kwinrulesrc
echo "   Done"

echo "[5/7] Restoring firefox.conf..."
mkdir -p ~/.config/environment.d
cp "$BACKUP_DIR/firefox.conf" ~/.config/environment.d/firefox.conf
echo "   Done"

echo "[6/7] Restoring kwin-fixes.conf (DDC disable)..."
cp "$BACKUP_DIR/environment.d/kwin-fixes.conf" ~/.config/environment.d/kwin-fixes.conf
echo "   Done"

echo "[7/7] Setting Balanced power profile..."
asusctl profile -P Balanced 2>/dev/null || true
echo "   Done"

echo ""
echo "========================================"
echo "  Configuration Restored!"
echo "========================================"
echo ""
echo "Please LOG OUT and LOG IN to apply changes."
echo ""
echo "If internal display is missing after reboot:"
echo "  sudo nano /etc/environment"
echo "  Remove any KWIN_DRM_DEVICES line"
echo "  Reboot"
