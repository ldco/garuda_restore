#!/bin/bash
# ============================================================================
# Fix Sleep/Wake Issues - Symptom-Driven Entrypoint
# ============================================================================
# Single orchestration command that routes to the appropriate fix based on
# the user's reported symptom.
#
# Usage:
#   sudo ./scripts/fix-sleep.sh
#
# This script will:
# 1. Diagnose your sleep/wake issue via interactive prompts
# 2. Route to the appropriate fix script
# 3. Apply the fix with proper validation
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KWIN_FIX_SCRIPT="$SCRIPT_DIR/fix-sleep-kwin.sh"
SDDM_FIX_SCRIPT="$SCRIPT_DIR/fix-sddm-input.sh"

# ============================================================================
# Header
# ============================================================================
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}         Sleep/Wake Issue Resolution${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# Check root privileges
# ============================================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    echo ""
    echo "Usage:"
    echo "  sudo ./scripts/fix-sleep.sh"
    echo ""
    exit 1
fi

# ============================================================================
# Verify internal scripts exist
# ============================================================================
if [ ! -f "$KWIN_FIX_SCRIPT" ]; then
    echo -e "${RED}Error: KWin fix script not found at $KWIN_FIX_SCRIPT${NC}"
    exit 1
fi

if [ ! -f "$SDDM_FIX_SCRIPT" ]; then
    echo -e "${RED}Error: SDDM fix script not found at $SDDM_FIX_SCRIPT${NC}"
    exit 1
fi

# ============================================================================
# Symptom Selection
# ============================================================================
echo -e "${CYAN}Please select the symptom that matches your issue:${NC}"
echo ""
echo "  1) Login screen works, but DESKTOP FREEZES after login"
echo "     → Screen is unresponsive, can't move windows, apps don't respond"
echo "     → Only Alt+PrtScn+B (kernel reboot) recovers the system"
echo "     → Caused by: KWin compositor failing to restore GPU state"
echo ""
echo "  2) LOGIN SCREEN ITSELF doesn't accept keyboard/mouse input"
echo "     → Can see the login screen, but can't type password"
echo "     → Mouse may or may not work"
echo "     → Caused by: Input devices staying suspended after wake"
echo ""
echo "  3) BOTH symptoms occur"
echo "     → Apply both fixes in the correct order"
echo ""
echo "  4) Show diagnostic information"
echo "     → Check current sleep state and installed fixes"
echo ""
echo "  5) Exit without making changes"
echo ""

read -p "Enter your choice [1-5]: " -n 1 -r
echo ""

case $REPLY in
    1)
        # Post-login freeze → KWin fix
        echo ""
        echo -e "${CYAN}Diagnosed: Post-login freeze after sleep${NC}"
        echo "Solution: KWin compositor recovery hook"
        echo ""
        echo "This fix will:"
        echo "  • Reset Intel backlight controller after wake"
        echo "  • Force DRM/display subsystem reprobe"
        echo "  • Restart KWin compositor via D-Bus"
        echo "  • Log GPU power state for thermal monitoring"
        echo ""
        read -p "Apply KWin fix now? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BOLD}Running KWin fix...${NC}"
            echo ""
            bash "$KWIN_FIX_SCRIPT"
            echo ""
            echo -e "${GREEN}✓ KWin fix applied successfully${NC}"
        else
            echo "KWin fix not applied."
        fi
        ;;

    2)
        # Login screen input frozen → SDDM fix
        echo ""
        echo -e "${CYAN}Diagnosed: Login screen input frozen after sleep${NC}"
        echo "Solution: SDDM input reprobe + health check hook"
        echo ""
        echo "This fix will:"
        echo "  • Re-probe input devices via udevadm trigger"
        echo "  • Enable wakeup for suspended input devices"
        echo "  • Run SDDM health checks after resume"
        echo "  • Restart SDDM service only if health checks fail"
        echo "  • Skip recovery if user session is active (safe)"
        echo ""
        read -p "Apply SDDM fix now? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BOLD}Running SDDM fix...${NC}"
            echo ""
            bash "$SDDM_FIX_SCRIPT"
            echo ""
            echo -e "${GREEN}✓ SDDM fix applied successfully${NC}"
        else
            echo "SDDM fix not applied."
        fi
        ;;

    3)
        # Both symptoms → Apply both fixes
        echo ""
        echo -e "${CYAN}Diagnosed: Both symptoms occur${NC}"
        echo "Solution: Apply both fixes in sequence"
        echo ""
        echo "Order of application:"
        echo "  1. KWin fix (post-login freeze)"
        echo "  2. SDDM fix (login screen input)"
        echo ""
        read -p "Apply both fixes now? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            echo -e "${BOLD}[1/2] Running KWin fix...${NC}"
            echo ""
            bash "$KWIN_FIX_SCRIPT"
            echo ""
            echo -e "${GREEN}✓ KWin fix applied${NC}"
            echo ""
            echo "─────────────────────────────────────────────────────────────"
            echo ""
            echo -e "${BOLD}[2/2] Running SDDM fix...${NC}"
            echo ""
            bash "$SDDM_FIX_SCRIPT"
            echo ""
            echo -e "${GREEN}✓ Both fixes applied successfully${NC}"
        else
            echo "No fixes applied."
        fi
        ;;

    4)
        # Diagnostics
        echo ""
        echo -e "${CYAN}=== Sleep/Wake Diagnostics ===${NC}"
        echo ""

        # Current sleep mode
        echo "Current sleep mode:"
        if [ -f /sys/power/mem_sleep ]; then
            cat /sys/power/mem_sleep
        else
            echo "  Unable to read sleep mode"
        fi
        echo ""

        # Installed hooks
        echo "Installed sleep hooks:"
        for hook in /etc/systemd/system-sleep/* /usr/lib/systemd/system-sleep/*; do
            if [ -f "$hook" ]; then
                if [[ "$hook" == *"kwin"* || "$hook" == *"sddm"* ]]; then
                    echo "  • $hook"
                fi
            fi
        done
        echo ""

        # SDDM fix status
        if [ -f /etc/systemd/system-sleep/sddm-input-reset ]; then
            echo -e "SDDM input fix: ${GREEN}Installed${NC}"
        elif [ -f /usr/lib/systemd/system-sleep/sddm-input-reset ]; then
            echo -e "SDDM input fix: ${YELLOW}Installed (old location - should migrate)${NC}"
        else
            echo -e "SDDM input fix: ${RED}Not installed${NC}"
        fi

        # KWin fix status
        if [ -f /etc/systemd/system-sleep/99-kwin-fix ]; then
            echo -e "KWin fix: ${GREEN}Installed${NC}"
        elif [ -f /usr/lib/systemd/system-sleep/99-kwin-fix ]; then
            echo -e "KWin fix: ${YELLOW}Installed (old location - should migrate)${NC}"
        else
            echo -e "KWin fix: ${RED}Not installed${NC}"
        fi
        echo ""

        # Recent sleep logs
        echo "Recent sleep log entries:"
        if [ -f /var/log/kwin-sleep.log ]; then
            echo "  KWin log: $(tail -1 /var/log/kwin-sleep.log 2>/dev/null || echo "empty")"
        fi
        if [ -f /var/log/sddm-input-reset.log ]; then
            echo "  SDDM log: $(tail -1 /var/log/sddm-input-reset.log 2>/dev/null || echo "empty")"
        fi
        echo ""

        echo "Run this script again and select a fix to apply."
        ;;

    5)
        # Exit
        echo "Exiting without changes."
        exit 0
        ;;

    *)
        echo -e "${RED}Invalid option. Please run again and select 1-5.${NC}"
        exit 1
        ;;
esac

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                    Next Steps${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Test immediately: systemctl suspend"
echo "2. Wake system and verify the issue is resolved"
echo "3. Check logs if needed:"
echo "   • KWin fix:    tail -f /var/log/kwin-sleep.log"
echo "   • SDDM fix:    tail -f /var/log/sddm-input-reset.log"
echo ""
echo -e "${GREEN}✓ Done${NC}"
