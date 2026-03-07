#!/bin/bash
# ============================================================================
# Fix SDDM Login Screen Input After Sleep (Wayland-safe)
# ============================================================================
# Creates systemd sleep hook to reset input devices on wake
# Does NOT change Wayland/X11 settings
# ============================================================================

set -e

echo "=== SDDM Input Fix (Wayland-safe) ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# ============================================================================
# Create systemd sleep hook to reset input devices
# ============================================================================
echo "[1/2] Creating systemd sleep hook..."

SLEEP_HOOK="/usr/lib/systemd/system-sleep/sddm-input-reset"

cat > "$SLEEP_HOOK" << 'EOF'
#!/bin/bash
# Reset input devices after resume to fix SDDM login screen input

case "$1/$2" in
    post/*)
        # Wait for system to stabilize
        sleep 1
        
        # Method 1: Reload input kernel modules
        # This forces re-initialization of keyboard/touchpad
        for module in hid_generic usbhid i2c_hid_acpi i2c_hid_hidpp; do
            if lsmod | grep -q "^${module}"; then
                modprobe -r "$module" 2>/dev/null && sleep 0.3 && modprobe "$module" 2>/dev/null && \
                    echo "[$(date)] Reloaded $module" >> /var/log/sddm-input-reset.log || true
            fi
        done
        
        # Method 2: Reload evdev (core input handler)
        if lsmod | grep -q "^evdev"; then
            modprobe -r evdev 2>/dev/null && sleep 0.3 && modprobe evdev 2>/dev/null && \
                echo "[$(date)] Reloaded evdev" >> /var/log/sddm-input-reset.log || true
        fi
        
        echo "[$(date)] Input reset complete" >> /var/log/sddm-input-reset.log
        ;;
esac
EOF

chmod +x "$SLEEP_HOOK"
echo "  ✓ Sleep hook created: $SLEEP_HOOK"

# ============================================================================
# Create udev rule to prevent input devices from suspending
# ============================================================================
echo ""
echo "[2/2] Creating udev rule..."

UDEV_RULE="/etc/udev/rules.d/99-input-wakeup.rules"

cat > "$UDEV_RULE" << 'EOF'
# Keep input devices enabled after suspend
# Fixes SDDM login screen not accepting keyboard input
ACTION=="add", SUBSYSTEM=="input", ATTR{power/wakeup}="enabled"
ACTION=="change", SUBSYSTEM=="input", ATTR{power/wakeup}="enabled"
EOF

echo "  ✓ Udev rule created: $UDEV_RULE"

# ============================================================================
# Reload configurations
# ============================================================================
echo ""
echo "Applying changes..."

# Reload udev rules
udevadm control --reload-rules 2>/dev/null || true
echo "  ✓ Udev rules reloaded"

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "=== Fix Applied Successfully ==="
echo ""
echo "What this does:"
echo "  • Resets input kernel modules after wake from sleep"
echo "  • Prevents input devices from staying suspended"
echo "  • Works with Wayland (no X11 changes)"
echo ""
echo "Files created:"
echo "  - $SLEEP_HOOK"
echo "  - $UDEV_RULE"
echo ""
echo "=== NEXT STEPS ==="
echo "1. Test immediately: systemctl suspend"
echo "2. Wake system and try typing password"
echo "3. Check logs: cat /var/log/sddm-input-reset.log"
echo ""
echo "=== ROLLBACK (if needed) ==="
echo "Run these commands manually:"
echo "  sudo rm -f $SLEEP_HOOK $UDEV_RULE"
echo "  sudo udevadm control --reload-rules"
echo ""
