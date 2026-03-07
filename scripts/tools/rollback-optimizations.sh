#!/bin/bash
# ============================================================================
# Rollback Hardware Optimizations
# ============================================================================
# Reverts all hardware-specific optimizations applied by apply-optimizations.sh
# Use this if you experience issues after optimizations were applied.
#
# Usage:
#   ./rollback-optimizations.sh              # Rollback all
#   ./rollback-optimizations.sh --category GPU  # Rollback only GPU
#   ./rollback-optimizations.sh --dry-run    # Show what would be reverted
# ============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Modes
DRY_RUN=false
CATEGORY="all"
[[ "$1" == "--dry-run" ]] && DRY_RUN=true
[[ "$1" == "--category" || "$1" == "-c" ]] && CATEGORY="$2"

# Track rolled back items
declare -a ROLLED_BACK=()
declare -a SKIPPED=()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_rolled() {
    echo -e "   ${GREEN}✓${NC} $1"
    ROLLED_BACK+=("$1")
}

log_skipped() {
    echo -e "   ${YELLOW}⊘${NC} $1"
    SKIPPED+=("$1")
}

log_info() {
    echo -e "   ${CYAN}ℹ${NC} $1"
}

run_or_show() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "   ${CYAN}[DRY-RUN]${NC} Would run: $1"
    else
        eval "$1"
    fi
}

# ============================================================================
# MAIN
# ============================================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}          Rollback Hardware Optimizations${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}=== DRY RUN MODE - No changes will be made ===${NC}"
    echo ""
fi

# ============================================================================
# 1. GPU OPTIMIZATIONS ROLLBACK
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "GPU" || "$CATEGORY" == "gpu" ]]; then
    echo -e "${BOLD}[GPU] Graphics Optimizations Rollback${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # Remove NVIDIA DRM modeset
    if grep -q "nvidia_drm.modeset=1" /etc/default/grub 2>/dev/null; then
        echo "   Removing nvidia_drm.modeset=1..."
        run_or_show "sudo sed -i 's/ nvidia_drm.modeset=1//' /etc/default/grub"
        log_rolled "nvidia_drm.modeset=1 removed"
    else
        log_skipped "nvidia_drm.modeset=1 not set"
    fi

    # Remove NVIDIA framebuffer device
    if grep -q "nvidia_drm.fbdev=1" /etc/default/grub 2>/dev/null; then
        echo "   Removing nvidia_drm.fbdev=1..."
        run_or_show "sudo sed -i 's/ nvidia_drm.fbdev=1//' /etc/default/grub"
        log_rolled "nvidia_drm.fbdev=1 removed"
    else
        log_skipped "nvidia_drm.fbdev=1 not set"
    fi

    # Remove AMD SG display
    if grep -q "amdgpu.sg_display=0" /etc/default/grub 2>/dev/null; then
        echo "   Removing amdgpu.sg_display=0..."
        run_or_show "sudo sed -i 's/ amdgpu.sg_display=0//' /etc/default/grub"
        log_rolled "amdgpu.sg_display=0 removed"
    else
        log_skipped "amdgpu.sg_display=0 not set"
    fi

    # Remove Intel PSR
    if grep -q "i915.enable_psr=0" /etc/default/grub 2>/dev/null; then
        echo "   Removing i915.enable_psr=0..."
        run_or_show "sudo sed -i 's/ i915.enable_psr=0//' /etc/default/grub"
        log_rolled "i915.enable_psr=0 removed"
    else
        log_skipped "i915.enable_psr=0 not set"
    fi

    echo ""
fi

# ============================================================================
# 2. KWIN OPTIMIZATIONS ROLLBACK
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "KWin" || "$CATEGORY" == "kwin" || "$CATEGORY" == "display" ]]; then
    echo -e "${BOLD}[KWin] Compositor Optimizations Rollback${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # Remove KWin DRM direct scanout disable
    if grep -q "KWIN_DRM_NO_DIRECT_SCANOUT=1" /etc/environment 2>/dev/null; then
        echo "   Removing KWIN_DRM_NO_DIRECT_SCANOUT=1..."
        run_or_show "sudo sed -i '/KWIN_DRM_NO_DIRECT_SCANOUT=1/d' /etc/environment"
        log_rolled "KWIN_DRM_NO_DIRECT_SCANOUT=1 removed from /etc/environment"
    else
        log_skipped "KWIN_DRM_NO_DIRECT_SCANOUT=1 not set"
    fi

    # Remove PowerDevil DDC disable
    if [ -f "$HOME/.config/environment.d/kwin-fixes.conf" ]; then
        echo "   Removing POWERDEVIL_NO_DDCUTIL=1..."
        run_or_show "rm -f $HOME/.config/environment.d/kwin-fixes.conf"
        log_rolled "kwin-fixes.conf removed"
    else
        log_skipped "kwin-fixes.conf not found"
    fi

    # Re-enable blur (optional - user choice)
    echo "   Note: KWin blur effects remain disabled (user preference)"
    log_skipped "Blur settings preserved (manual change if needed)"

    echo ""
fi

# ============================================================================
# 3. POWER MANAGEMENT ROLLBACK
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "power" || "$CATEGORY" == "Power" ]]; then
    echo -e "${BOLD}[Power] Power Management Rollback${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # Reset ASUS profile to default (let power-profiles-daemon handle it)
    if command -v asusctl &>/dev/null; then
        echo "   Resetting ASUS profile to default..."
        run_or_show "asusctl profile -P Balanced 2>/dev/null || true"
        log_rolled "ASUS profile reset to Balanced"
    else
        log_skipped "asusctl not available"
    fi

    # Disable power-profiles-daemon (optional)
    echo "   Note: power-profiles-daemon remains enabled (required for desktop)"
    log_skipped "power-profiles-daemon preserved"

    echo ""
fi

# ============================================================================
# 4. MEMORY & SWAP ROLLBACK
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "memory" || "$CATEGORY" == "Memory" ]]; then
    echo -e "${BOLD}[Memory] Swap & ZRAM Rollback${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # Reset swappiness to default
    if [ -f /etc/sysctl.d/99-swappiness.conf ]; then
        echo "   Removing custom swappiness setting..."
        run_or_show "sudo rm -f /etc/sysctl.d/99-swappiness.conf"
        log_rolled "swappiness config removed (reverts to default 60)"
    else
        log_skipped "swappiness config not found"
    fi

    # Remove VM dirty ratios
    if [ -f /etc/sysctl.d/99-vm.conf ]; then
        echo "   Removing VM dirty ratio settings..."
        run_or_show "sudo rm -f /etc/sysctl.d/99-vm.conf"
        log_rolled "VM dirty ratios removed"
    else
        log_skipped "VM dirty config not found"
    fi

    echo ""
fi

# ============================================================================
# 5. I/O SCHEDULER ROLLBACK
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "io" || "$CATEGORY" == "storage" ]]; then
    echo -e "${BOLD}[I/O] Storage Scheduler Rollback${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # Remove NVMe scheduler rule
    if [ -f /etc/udev/rules.d/60-scheduler.rules ]; then
        echo "   Removing NVMe scheduler udev rule..."
        run_or_show "sudo rm -f /etc/udev/rules.d/60-scheduler.rules"
        log_rolled "NVMe scheduler rule removed (reverts to default)"
    else
        log_skipped "scheduler rule not found"
    fi

    echo ""
fi

# ============================================================================
# 6. FIREWALL ROLLBACK
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "security" || "$CATEGORY" == "Security" ]]; then
    echo -e "${BOLD}[Security] Firewall Rollback${NC}"
    echo "─────────────────────────────────────────────────────────────"

    # Disable firewalld (user choice)
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        echo "   ⚠ Firewalld is currently active"
        echo ""
        read -p "Disable firewalld? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            run_or_show "sudo systemctl disable --now firewalld"
            log_rolled "Firewalld disabled"
        else
            log_skipped "Firewalld remains enabled (user choice)"
        fi
    else
        log_skipped "Firewalld not active"
    fi

    echo ""
fi

# ============================================================================
# SUMMARY
# ============================================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}                    Summary${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Rolled back:  ${GREEN}${#ROLLED_BACK[@]}${NC}"
echo -e "Skipped:      ${YELLOW}${#SKIPPED[@]}${NC}"
echo ""

if [ ${#ROLLED_BACK[@]} -gt 0 ]; then
    echo -e "${CYAN}Rolled Back:${NC}"
    for item in "${ROLLED_BACK[@]}"; do
        echo "   • $item"
    done
    echo ""
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped (not applicable):${NC}"
    for item in "${SKIPPED[@]}"; do
        echo "   • $item"
    done
    echo ""
fi

# Check if GRUB was modified
if grep -qE "nvidia_drm|amdgpu|i915.enable_psr" /etc/default/grub 2>/dev/null; then
    echo -e "${YELLOW}⚠ GRUB still contains kernel parameters.${NC}"
else
    echo -e "${GREEN}✓ GRUB is clean.${NC}"
fi

echo ""

# Reboot reminder
if [ ${#ROLLED_BACK[@]} -gt 0 ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  IMPORTANT: Reboot required for all changes to take effect${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Run: sudo reboot"
    echo ""
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}=== DRY RUN COMPLETE - No changes were made ===${NC}"
fi

echo -e "${GREEN}✓ Rollback complete${NC}"
