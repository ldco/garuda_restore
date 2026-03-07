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
# PREFLIGHT: Verify /etc/systemd/system-sleep exists or create it
# ============================================================================
echo -e "${CYAN}[1/4] Verifying sleep hook directory...${NC}"

SLEEP_HOOK_DIR="/etc/systemd/system-sleep"

if [ -d "$SLEEP_HOOK_DIR" ]; then
    echo -e "   ${GREEN}✓${NC} Directory exists: $SLEEP_HOOK_DIR"
else
    echo "   Creating directory: $SLEEP_HOOK_DIR"
    if mkdir -p "$SLEEP_HOOK_DIR" 2>/dev/null; then
        chmod 755 "$SLEEP_HOOK_DIR"
        echo -e "   ${GREEN}✓${NC} Directory created: $SLEEP_HOOK_DIR"
    else
        echo -e "   ${RED}✗${NC} Failed to create directory: $SLEEP_HOOK_DIR"
        echo ""
        echo "   Error: Cannot create sleep hook directory."
        echo "   Please ensure you have root privileges and the filesystem is writable."
        echo ""
        exit 1
    fi
fi

# ============================================================================
# MIGRATION: Remove old hook from /usr/lib if it exists
# ============================================================================
echo ""
echo -e "${CYAN}[2/4] Migrating from /usr/lib to /etc...${NC}"

OLD_SLEEP_HOOK="/usr/lib/systemd/system-sleep/sddm-input-reset"
NEW_SLEEP_HOOK="/etc/systemd/system-sleep/sddm-input-reset"

if [ -f "$OLD_SLEEP_HOOK" ]; then
    echo "   Found old hook at $OLD_SLEEP_HOOK"
    rm -f "$OLD_SLEEP_HOOK"
    echo -e "   ${GREEN}✓${NC} Removed old hook (will be replaced in /etc)"
else
    echo "   No old hook found"
fi

# ============================================================================
# Create systemd sleep hook to reset input devices
# ============================================================================
echo ""
echo -e "${CYAN}[3/4] Creating systemd sleep hook...${NC}"

SLEEP_HOOK="$NEW_SLEEP_HOOK"

cat > "$SLEEP_HOOK" << 'EOF'
#!/bin/bash
# Reset input devices after resume to fix SDDM login screen input
# Wayland-safe: uses udevadm trigger instead of module unload
# Includes health checks and bounded fallback recovery for hung greeter
#
# SAFETY: SDDM restart is ONLY performed when system is at login screen,
# NOT when a user session is active (prevents data loss/logout)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/sddm-input-reset.log
}

# Check if system is at SDDM login screen (no active user session)
# Returns 0 if at login screen, 1 if user session is active, 2 if uncertain
# Uses structured loginctl show-session/show-seat queries (no text parsing)
is_at_login_screen() {
    local seat_id="seat0"
    local session_id
    local session_state
    local session_class

    # Method 1: Query seat's active session via loginctl (structured output)
    # loginctl show-seat returns the active session ID for the seat
    session_id=$(loginctl show-seat "$seat_id" --value --property=ActiveSession 2>/dev/null | head -1)
    
    if [[ -n "$session_id" && "$session_id" != "" ]]; then
        # Session exists for this seat - check its properties
        # Use loginctl show-session with --value for structured output
        session_state=$(loginctl show-session "$session_id" --value --property=State 2>/dev/null | head -1)
        session_class=$(loginctl show-session "$session_id" --value --property=Class 2>/dev/null | head -1)
        
        # Validate: session lookup succeeded
        if [[ -n "$session_state" && "$session_state" != "" ]]; then
            # Active user session (not greeter) = NOT at login screen
            if [[ "$session_state" == "active" && "$session_class" != "greeter" ]]; then
                log "Session $session_id: state=$session_state, class=$session_class"
                return 1  # User session active
            fi
            # Session is greeter or not active = at login screen
            if [[ "$session_class" == "greeter" ]]; then
                log "Session $session_id: state=$session_state, class=$session_class (greeter)"
                return 0  # At login screen
            fi
        fi
    fi

    # Method 2: Check for any active non-greeter sessions (fallback)
    # Use loginctl list-sessions with --no-legend and parse structured fields
    local sessions
    sessions=$(loginctl list-sessions --no-legend 2>/dev/null || echo "")
    
    if [[ -n "$sessions" ]]; then
        while read -r sid uid user seat session_class_rest state_rest; do
            # Skip empty lines
            [[ -z "$sid" ]] && continue
            
            # Get structured session class
            local sclass
            sclass=$(loginctl show-session "$sid" --value --property=Class 2>/dev/null | head -1)
            
            # Get structured session state
            local sstate
            sstate=$(loginctl show-session "$sid" --value --property=State 2>/dev/null | head -1)
            
            # Active non-greeter session = user logged in
            if [[ "$sstate" == "active" && "$sclass" != "greeter" ]]; then
                log "Found active user session: $sid (class=$sclass, state=$sstate)"
                return 1  # User session active
            fi
        done <<< "$sessions"
    fi

    # Method 3: Check if SDDM greeter is running (indicates login screen)
    if pgrep -x sddm >/dev/null 2>&1 && pgrep -f "sddm-greeter" >/dev/null 2>&1; then
        log "SDDM greeter detected (no active user session)"
        return 0  # At login screen
    fi

    # Method 4: Check for Plasma/KWin sessions (user logged in)
    if pgrep -f "plasma-session\|kwin_wayland\|startplasma" >/dev/null 2>&1; then
        log "Plasma session detected (user logged in)"
        return 1  # User session active
    fi

    # Default: UNCERTAIN - skip SDDM restart to be safe
    log "Unable to determine session state (loginctl/session lookup failed)"
    return 2  # Uncertain - do not restart SDDM
}

case "$1/$2" in
    post/*)
        log "=== RESUME ==="

        # Wait for system to stabilize
        sleep 1

        # Method: Trigger udev to re-probe input devices
        # This is safer than unloading kernel modules on a live system
        # ALWAYS RUN: Input reprobe is safe regardless of session state
        if udevadm trigger --subsystem-match=input --action=add 2>/dev/null; then
            log "Input devices re-probed via udevadm"
        else
            log "WARNING: udevadm trigger failed"
        fi

        # Optional: Also try to wake up any suspended input devices
        for dev in /sys/class/input/*/device/power/wakeup; do
            if [ -f "$dev" ]; then
                echo enabled > "$dev" 2>/dev/null || true
            fi
        done

        # ========================================================================
        # SESSION STATE CHECK: Only run SDDM health checks at login screen
        # ========================================================================
        is_at_login_screen
        SESSION_STATE=$?
        
        if [[ $SESSION_STATE -eq 0 ]]; then
            log "Session state: At SDDM login screen (no active user session)"
            # Continue to health checks
        elif [[ $SESSION_STATE -eq 1 ]]; then
            log "Session state: User session active - SKIPPING SDDM health checks/restart"
            log "Input reprobe completed - SDDM recovery skipped to prevent data loss"
            log "=== RESUME COMPLETE ==="
            exit 0
        else
            # SESSION_STATE -eq 2: Uncertain
            log "Session state: UNCERTAIN - SKIPPING SDDM health checks/restart (safe fallback)"
            log "Input reprobe completed - SDDM restart skipped (cannot verify session state)"
            log "=== RESUME COMPLETE ==="
            exit 0
        fi

        # ========================================================================
        # HEALTH CHECK: Verify SDDM greeter is responsive (login screen only)
        # ========================================================================
        log "Running SDDM health check..."

        SDDM_HEALTHY=false
        MAX_RETRIES=3
        RETRY_COUNT=0
        RETRY_DELAY=2

        while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ "$SDDM_HEALTHY" = "false" ]; do
            RETRY_COUNT=$((RETRY_COUNT + 1))
            log "Health check attempt $RETRY_COUNT/$MAX_RETRIES"

            # Check 1: Is SDDM process running?
            if ! pgrep -x sddm >/dev/null 2>&1; then
                log "FAIL: SDDM process not running"
                sleep $RETRY_DELAY
                continue
            fi
            log "PASS: SDDM process running"

            # Check 2: Is SDDM greeter process running?
            if ! pgrep -f "sddm-greeter" >/dev/null 2>&1; then
                log "FAIL: SDDM greeter process not running"
                sleep $RETRY_DELAY
                continue
            fi
            log "PASS: SDDM greeter process running"

            # Check 3: Can we communicate with SDDM via D-Bus?
            # SDDM exposes org.freedesktop.DisplayManager on system bus
            if dbus-send --system --print-reply --dest=org.freedesktop.DisplayManager \
                /org/freedesktop/DisplayManager \
                org.freedesktop.DBus.Properties.Get \
                string:org.freedesktop.DisplayManager \
                string:Seats >/dev/null 2>&1; then
                log "PASS: SDDM D-Bus interface responsive"
                SDDM_HEALTHY=true
            else
                log "FAIL: SDDM D-Bus interface not responsive"
                sleep $RETRY_DELAY
            fi
        done

        # ========================================================================
        # FALLBACK RECOVERY: Restart SDDM if health checks failed (login screen only)
        # ========================================================================
        if [ "$SDDM_HEALTHY" = "false" ]; then
            log "WARNING: SDDM health checks failed after $MAX_RETRIES attempts"
            log "Initiating bounded fallback recovery..."

            # Bounded recovery: Only restart SDDM service
            # This is idempotent - if SDDM is already stopped, start will work
            # If SDDM is hung, restart will recover it
            # Guard: Only attempt once per resume cycle to avoid restart loops

            RECOVERY_MARKER="/run/sddm-recovery-$$"
            if [ ! -f "$RECOVERY_MARKER" ]; then
                touch "$RECOVERY_MARKER"

                log "Attempting SDDM service restart..."

                # Try systemctl first (preferred method)
                if systemctl restart sddm 2>/dev/null; then
                    log "SUCCESS: SDDM service restarted via systemctl"
                else
                    # Fallback: try direct service command
                    if service sddm restart 2>/dev/null; then
                        log "SUCCESS: SDDM service restarted via service command"
                    else
                        log "FAIL: Could not restart SDDM service"
                    fi
                fi

                # Clean up marker after delay (allow time for restart)
                (sleep 30; rm -f "$RECOVERY_MARKER") &
            else
                log "SKIP: Recovery already attempted this resume cycle (marker exists)"
            fi
        else
            log "SUCCESS: SDDM health check passed"
        fi

        log "=== RESUME COMPLETE ==="
        ;;
esac
EOF

chmod +x "$SLEEP_HOOK"
echo -e "   ${GREEN}✓${NC} Sleep hook created: $SLEEP_HOOK"

# ============================================================================
# Create udev rule to prevent input devices from suspending
# ============================================================================
echo ""
echo -e "${CYAN}[4/4] Creating udev rule...${NC}"

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
echo "  • ${GREEN}NEW:${NC} Session-aware: Only checks/restarts SDDM at login screen"
echo "  • ${GREEN}NEW:${NC} Skips recovery when user session active (prevents data loss)"
echo ""
echo "Session detection (structured loginctl queries):"
echo "  • Uses loginctl show-seat/show-session (no text parsing)"
echo "  • Validates session state and class properties"
echo "  • Safe fallback: skips SDDM restart if session state uncertain"
echo ""
echo "Health checks (login screen ONLY):"
echo "  1. SDDM process running"
echo "  2. SDDM greeter process running"
echo "  3. SDDM D-Bus interface responsive"
echo ""
echo "Recovery (login screen ONLY):"
echo "  • Retries health checks up to 3 times"
echo "  • Restarts SDDM service only if all checks fail"
echo "  • Guard: One recovery attempt per resume cycle (prevents loops)"
echo "  • ${GREEN}SAFE:${NC} Never restarts SDDM when user session is active"
echo "  • ${GREEN}SAFE:${NC} Skips restart if session state cannot be determined"
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
echo "  sudo rm -f $NEW_SLEEP_HOOK $UDEV_RULE"
echo "  sudo udevadm control --reload-rules"
echo ""
echo "Note: Hooks are now in /etc (not /usr/lib) to survive package updates"
echo ""
