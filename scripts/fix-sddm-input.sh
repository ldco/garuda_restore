#!/bin/bash
# ============================================================================
# Fix SDDM Login Screen Input After Sleep (Wayland-safe)
# ============================================================================
# Creates systemd sleep hook to reset input devices on wake
# 
# CHANGES FROM ORIGINAL:
# - Removed modprobe -r evdev (unsafe on live system)
# - Uses udevadm trigger instead (safe device re-probe)
# - Does NOT change Wayland/X11 settings
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
echo -e "${BOLD}      SDDM Input Fix (Wayland-safe)${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run with sudo${NC}"
    exit 1
fi

# ============================================================================
# Create systemd sleep hook to reset input devices
# ============================================================================
echo -e "${CYAN}[1/2] Creating systemd sleep hook...${NC}"

SLEEP_HOOK="/usr/lib/systemd/system-sleep/sddm-input-reset"

cat > "$SLEEP_HOOK" << 'EOF'
#!/bin/bash
# Reset input devices after resume to fix SDDM login screen input
# Wayland-safe: uses udevadm trigger instead of module unload

case "$1/$2" in
    post/*)
        # Wait for system to stabilize
        sleep 1

        # Method: Trigger udev to re-probe input devices
        # This is safer than unloading kernel modules on a live system
        udevadm trigger --subsystem-match=input --action=add 2>/dev/null && \
            echo "[$(date)] Input devices re-probed via udevadm" >> /var/log/sddm-input-reset.log || \
            echo "[$(date)] udevadm trigger failed" >> /var/log/sddm-input-reset.log

        # Optional: Also try to wake up any suspended input devices
        for dev in /sys/class/input/*/device/power/wakeup; do
            if [ -f "$dev" ]; then
                echo enabled > "$dev" 2>/dev/null || true
            fi
        done

        echo "[$(date)] Input reset complete" >> /var/log/sddm-input-reset.log
        ;;
esac
EOF

chmod +x "$SLEEP_HOOK"
echo -e "   ${GREEN}✓${NC} Sleep hook created: $SLEEP_HOOK"

# ============================================================================
# Create udev rule to prevent input devices from suspending
# ============================================================================
echo ""
echo -e "${CYAN}[2/2] Creating udev rule...${NC}"

UDEV_RULE="/etc/udev/rules.d/99-input-wakeup.rules"

cat > "$UDEV_RULE" << 'EOF'
# Keep input devices enabled after suspend
# Fixes SDDM login screen not accepting keyboard input
ACTION=="add", SUBSYSTEM=="input", ATTR{power/wakeup}="enabled"
ACTION=="change", SUBSYSTEM=="input", ATTR{power/wakeup}="enabled"
EOF

echo -e "   ${GREEN}✓${NC} Udev rule created: $UDEV_RULE"

# ============================================================================
# Reload configurations
# ============================================================================
echo ""
echo "Applying changes..."

# Reload udev rules
udevadm control --reload-rules 2>/dev/null && \
    echo -e "   ${GREEN}✓${NC} Udev rules reloaded" || \
    echo -e "   ${YELLOW}⚠${NC} Udev rules reload skipped (may need reboot)"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Fix Applied Successfully${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "What this does:"
echo "  • Re-probes input devices after wake via udevadm trigger"
echo "  • Prevents input devices from staying suspended"
echo "  • Works with Wayland (no X11 changes)"
echo "  • ${GREEN}SAFE:${NC} Does NOT unload kernel modules on live system"
echo ""
echo "Files created:"
echo "  - $SLEEP_HOOK"
echo "  - $UDEV_RULE"
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} NEXT STEPS${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo "1. Test immediately: systemctl suspend"
echo "2. Wake system and try typing password"
echo "3. Check logs: cat /var/log/sddm-input-reset.log"
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW} ROLLBACK (if needed)${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
echo "Run these commands manually:"
echo "  sudo rm -f $SLEEP_HOOK $UDEV_RULE"
echo "  sudo udevadm control --reload-rules"
echo ""
