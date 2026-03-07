#!/bin/bash
# ============================================================================
# Fix: KWin Freeze After Sleep (KDE Plasma Wayland)
# ============================================================================
# Symptom: SDDM login works, can enter password, but desktop freezes after login
#          Only Alt+PrtScn+B recovers (kernel reboot - confirms KWin is dead)
# Cause: KWin compositor fails to restore GPU state after suspend on hybrid GPU
# ============================================================================

set -e

echo "=== KWin Sleep Freeze Fix (KDE Plasma Wayland) ==="
echo ""

if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo"
    exit 1
fi

# ============================================================================
# PREFLIGHT: Check for risky GRUB parameters
# ============================================================================
echo "[PREFLIGHT] Checking /etc/default/grub for disallowed parameters..."
echo ""

GRUB_CONFIG="/etc/default/grub"
GRUB_CONFIG_AVAILABLE=0
RISKY_PARAMS_FOUND=0

# Check if GRUB config exists and is readable
if [ -f "$GRUB_CONFIG" ] && [ -r "$GRUB_CONFIG" ]; then
    GRUB_CONFIG_AVAILABLE=1
    echo "  • GRUB config found: $GRUB_CONFIG"
    
    # Parameters that cause thermal instability per SLEEP-WAKE-ISSUES.md
    declare -a RISKY_PARAMS=(
        "nvidia_drm.fbdev=1"
        "mem_sleep_default=deep"
        "mem_sleep_default=s2idle"
    )
    
    for param in "${RISKY_PARAMS[@]}"; do
        if grep -q "$param" "$GRUB_CONFIG" 2>/dev/null; then
            echo "  ⚠️  FOUND: $param"
            RISKY_PARAMS_FOUND=1
        fi
    done
    
    if [ $RISKY_PARAMS_FOUND -eq 1 ]; then
        echo ""
        echo "=== INSTALLATION ABORTED ==="
        echo ""
        echo "Risky GRUB parameters detected. These parameters cause thermal instability"
        echo "on this hardware (GPU stuck at 40W, system overheating to 96°C)."
        echo ""
        echo "See docs/SLEEP-WAKE-ISSUES.md for details."
        echo ""
        echo "=== ROLLBACK REQUIRED BEFORE INSTALLATION ==="
        echo ""
        echo "Run these commands to remove risky parameters:"
        echo ""
        echo "  sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub"
        echo "  sudo sed -i 's/mem_sleep_default=deep //' /etc/default/grub"
        echo "  sudo sed -i 's/mem_sleep_default=s2idle //' /etc/default/grub"
        echo "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
        echo ""
        echo "Then re-run this script."
        echo ""
        exit 1
    fi
    
    echo "  ✓ No risky GRUB parameters found"
else
    echo "  ⚠️  WARNING: $GRUB_CONFIG not found or not readable"
    echo ""
    echo "=== PREFLIGHT VALIDATION UNAVAILABLE ==="
    echo ""
    echo "This system may use a non-GRUB bootloader (systemd-boot, rEFInd, etc.)"
    echo "or the GRUB configuration is in a non-standard location."
    echo ""
    echo "The script cannot validate kernel parameters for thermal safety."
    echo ""
    echo "=== MANUAL CONFIRMATION REQUIRED ==="
    echo ""
    echo "Before proceeding, manually verify your bootloader config does NOT contain:"
    echo "  • nvidia_drm.fbdev=1"
    echo "  • mem_sleep_default=deep"
    echo "  • mem_sleep_default=s2idle"
    echo ""
    echo "These parameters cause thermal instability (GPU stuck at 40W, overheating to 96°C)."
    echo "See docs/SLEEP-WAKE-ISSUES.md for details."
    echo ""
    read -p "Type 'CONFIRM' to proceed with installation anyway: " CONFIRM
    if [ "$CONFIRM" != "CONFIRM" ]; then
        echo ""
        echo "Installation cancelled."
        exit 1
    fi
    echo ""
    echo "  ✓ Manual confirmation received - proceeding without GRUB validation"
fi
echo ""

# ============================================================================
# Check current sleep mode
# ============================================================================
CURRENT_SLEEP_MODE=$(cat /sys/power/mem_sleep 2>/dev/null | grep -o '\[.*\]' | tr -d '[]')
echo "[PREFLIGHT] Current sleep mode: $CURRENT_SLEEP_MODE"

if [ "$CURRENT_SLEEP_MODE" != "s2idle" ]; then
    echo "  ⚠️  Warning: Expected sleep mode is 's2idle' (system default)"
    echo "     Current mode '$CURRENT_SLEEP_MODE' may cause instability"
fi
echo ""

# ============================================================================
# Create sleep hook
# ============================================================================
echo "[1/2] Creating sleep recovery hook..."

HOOK="/usr/lib/systemd/system-sleep/99-kwin-fix"

cat > "$HOOK" << 'EOF'
#!/bin/bash
# Fix KWin freeze after suspend on hybrid GPU (Intel + NVIDIA)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/kwin-sleep.log
}

log_gpu_power() {
    # Log current NVIDIA GPU power state for debugging
    if [ -x /usr/bin/nvidia-smi ]; then
        local power_state
        power_state=$(nvidia-smi --query-gpu=power.draw,pstate --format=csv,noheader 2>/dev/null || echo "N/A")
        log "GPU power: $power_state"
    fi
}

case "$1/$2" in
    pre/*)
        log "=== SUSPEND ==="
        log_gpu_power
        ;;
    post/*)
        log "=== RESUME ==="
        log_gpu_power

        # Wait for display to initialize
        sleep 2

        # 1. Reset Intel backlight (common freeze trigger)
        for bl in /sys/class/backlight/*; do
            if [ -d "$bl" ] && [ -f "$bl/actual_brightness" ]; then
                curr=$(cat "$bl/actual_brightness" 2>/dev/null)
                if [ -n "$curr" ] && [ "$curr" -gt 0 ] 2>/dev/null; then
                    echo 0 > "$bl/brightness" 2>/dev/null || true
                    sleep 0.1
                    echo "$curr" > "$bl/brightness" 2>/dev/null || true
                    log "Backlight reset: $(basename $bl)"
                fi
            fi
        done

        # 2. Trigger DRM reprobe (force display re-detection)
        udevadm trigger --subsystem-match=drm --action=change 2>/dev/null && \
            log "DRM triggered" || true

        # 3. Refresh input devices
        udevadm trigger --subsystem-match=input --action=add 2>/dev/null && \
            log "Input refreshed" || true

        # 4. Restart KWin for active user sessions
        # This is the KEY fix - KWin is frozen and must restart
        # Env vars must be set INSIDE the user command (su - may drop injected vars)
        for uid in $(ls /run/user/ 2>/dev/null); do
            user=$(getent passwd "$uid" | cut -d: -f1)
            [ -z "$user" ] && continue

            # Define bus paths
            USER_XDG_RUNTIME_DIR="/run/user/$uid"
            USER_DBUS_ADDR="unix:path=$USER_XDG_RUNTIME_DIR/bus"

            # Verify bus socket exists before attempting restart
            if [ ! -S "$USER_XDG_RUNTIME_DIR/bus" ]; then
                log "KWin restart SKIPPED for $user (bus socket not found)"
                continue
            fi

            # Set env vars INSIDE the user shell before running D-Bus command
            # This ensures they persist even if su - strips parent environment
            if su - "$user" -c "XDG_RUNTIME_DIR='$USER_XDG_RUNTIME_DIR' DBUS_SESSION_BUS_ADDRESS='$USER_DBUS_ADDR' qdbus-qt6 org.kde.KWin /org/kde/KWin org.kde.KWin.restart" 2>/dev/null; then
                log "KWin restart SUCCESS for $user (qdbus-qt6)"
            elif su - "$user" -c "XDG_RUNTIME_DIR='$USER_XDG_RUNTIME_DIR' DBUS_SESSION_BUS_ADDRESS='$USER_DBUS_ADDR' qdbus org.kde.KWin /org/kde/KWin org.kde.KWin.restart" 2>/dev/null; then
                log "KWin restart SUCCESS for $user (qdbus)"
            else
                log "KWin restart FAILED for $user (command returned error)"
            fi
        done

        log_gpu_power
        log "=== RESUME COMPLETE ==="
        ;;
esac
EOF

chmod +x "$HOOK"
echo "  ✓ Hook: $HOOK"

# ============================================================================
# Note: No Polkit rule created
# KWin restart via D-Bus from system-sleep context works with existing permissions
# when called with proper user session context (su - user with XDG_RUNTIME_DIR)
# ============================================================================
echo ""
echo "[2/2] No Polkit rule needed"
echo "  • KWin restart uses existing D-Bus permissions"
echo "  • Called with proper user session context"

# ============================================================================
# Reload
# ============================================================================
echo ""
echo "Applying..."

udevadm control --reload-rules
systemctl daemon-reload

echo "  ✓ Done"

# ============================================================================
# Post-Install Summary
# ============================================================================
echo ""
echo "=== Applied ==="
echo ""
echo "What this does:"
echo "  • Resets Intel backlight after wake (common freeze trigger)"
echo "  • Forces DRM/display reprobe"
echo "  • Restarts KWin compositor with proper user session context"
echo "  • Logs GPU power state before/after for thermal monitoring"
echo ""
echo "=== Expected Baseline ==="
echo "  • Sleep mode: s2idle (system default)"
echo "  • GRUB parameters: quiet loglevel=3 nvidia_drm.modeset=1"
echo "  • No nvidia_drm.fbdev=1, mem_sleep_default=deep, or mem_sleep_default=s2idle"
echo ""
echo "Test: systemctl suspend"
echo "Logs: tail -f /var/log/kwin-sleep.log"
echo ""
echo "=== ROLLBACK ==="
echo "sudo rm -f $HOOK"
echo "sudo udevadm control --reload-rules"
