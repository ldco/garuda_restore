#!/bin/bash
# ============================================================================
# Apply Hardware-Specific Optimizations
# ============================================================================
# Applies optimizations conditionally based on detected hardware.
# Used by restore.sh after package installation.
#
# Usage:
#   ./apply-optimizations.sh              # Apply all applicable optimizations
#   ./apply-optimizations.sh --dry-run    # Show what would be applied
#   ./apply-optimizations.sh --category GPU  # Apply only GPU optimizations
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

# Script directory for detection script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/detect-hardware.sh"

# Track applied optimizations
declare -a APPLIED=()
declare -a SKIPPED=()

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

log_applied() {
    echo -e "   ${GREEN}✓${NC} $1"
    APPLIED+=("$1")
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
# DETECT HARDWARE
# ============================================================================

echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}          Hardware-Specific Optimizations${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════${NC}"
echo ""

# Run detection and parse JSON output
if [ ! -f "$DETECT_SCRIPT" ]; then
    echo -e "${RED}Error: detect-hardware.sh not found at $DETECT_SCRIPT${NC}"
    exit 1
fi

HARDWARE_JSON=$("$DETECT_SCRIPT" 2>/dev/null)

# Parse hardware profile (simple grep-based parsing)
HAS_NVIDIA=$(echo "$HARDWARE_JSON" | grep -o '"nvidia": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
HAS_AMD=$(echo "$HARDWARE_JSON" | grep -o '"amd": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
HAS_INTEL=$(echo "$HARDWARE_JSON" | grep -o '"intel": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
HYBRID_GPU=$(echo "$HARDWARE_JSON" | grep -o '"hybrid": *"[^"]*"' | cut -d':' -f2 | tr -d ' "')
MULTI_MONITOR=$(echo "$HARDWARE_JSON" | grep -o '"multi_monitor": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
HAS_NVME=$(echo "$HARDWARE_JSON" | grep -o '"nvme": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
HAS_ASUSCTL=$(echo "$HARDWARE_JSON" | grep -o '"asusctl": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
HAS_ZRAM=$(echo "$HARDWARE_JSON" | grep -o '"has_zram": *[a-z]*' | cut -d':' -f2 | tr -d ' ')
RAM_CATEGORY=$(echo "$HARDWARE_JSON" | grep -o '"category": *"[^"]*"' | cut -d':' -f2 | tr -d ' "')
MACHINE_TYPE=$(echo "$HARDWARE_JSON" | grep -o '"type": *"[^"]*"' | cut -d':' -f2 | tr -d ' "')

echo -e "${CYAN}Detected Hardware Profile:${NC}"
echo "   GPU: NVIDIA=$HAS_NVIDIA, AMD=$HAS_AMD, Intel=$HAS_INTEL"
echo "   Hybrid: $HYBRID_GPU"
echo "   Multi-Monitor: $MULTI_MONITOR"
echo "   Storage: NVMe=$HAS_NVME"
echo "   Machine: $MACHINE_TYPE"
echo "   ASUS Tools: $HAS_ASUSCTL"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}=== DRY RUN MODE - No changes will be made ===${NC}"
    echo ""
fi

# ============================================================================
# 1. GPU OPTIMIZATIONS
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "GPU" || "$CATEGORY" == "gpu" ]]; then
    echo -e "${BOLD}[GPU] Graphics Optimizations${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    # NVIDIA DRM modeset
    if [ "$HAS_NVIDIA" = "true" ]; then
        echo "   Applying NVIDIA DRM modeset..."
        if ! grep -q "nvidia_drm.modeset=1" /etc/default/grub 2>/dev/null; then
            run_or_show "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 nvidia_drm.modeset=1\"/' /etc/default/grub"
            log_applied "nvidia_drm.modeset=1 (Wayland support)"
        else
            log_info "nvidia_drm.modeset=1 already set"
        fi
        
        # NVIDIA framebuffer device (for internal display issues)
        # Only apply if laptop with hybrid GPU
        if [ "$MACHINE_TYPE" = "laptop" ] && [ "$HYBRID_GPU" = "intel-nvidia" ]; then
            if ! grep -q "nvidia_drm.fbdev=1" /etc/default/grub 2>/dev/null; then
                run_or_show "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 nvidia_drm.fbdev=1\"/' /etc/default/grub"
                log_applied "nvidia_drm.fbdev=1 (internal display fix)"
            else
                log_info "nvidia_drm.fbdev=1 already set"
            fi
        fi
    else
        log_skipped "NVIDIA not detected"
    fi
    
    # AMD GPU scatter/gather
    if [ "$HAS_AMD" = "true" ] && [ "$HAS_INTEL" = "false" ]; then
        echo "   Applying AMD SG display fix..."
        if ! grep -q "amdgpu.sg_display=0" /etc/default/grub 2>/dev/null; then
            run_or_show "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 amdgpu.sg_display=0\"/' /etc/default/grub"
            log_applied "amdgpu.sg_display=0 (flicker fix)"
        else
            log_info "amdgpu.sg_display=0 already set"
        fi
    fi
    
    # Intel PSR disable
    if [ "$HAS_INTEL" = "true" ] && [ "$HAS_NVIDIA" = "false" ] && [ "$HAS_AMD" = "false" ]; then
        echo "   Applying Intel PSR fix..."
        if ! grep -q "i915.enable_psr=0" /etc/default/grub 2>/dev/null; then
            run_or_show "sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 i915.enable_psr=0\"/' /etc/default/grub"
            log_applied "i915.enable_psr=0 (tearing fix)"
        else
            log_info "i915.enable_psr=0 already set"
        fi
    fi
    
    echo ""
fi

# ============================================================================
# 2. KWIN/COMPOSITOR OPTIMIZATIONS
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "KWin" || "$CATEGORY" == "kwin" || "$CATEGORY" == "display" ]]; then
    echo -e "${BOLD}[KWin] Compositor Optimizations${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    # KWin DRM direct scanout disable (multi-monitor + NVIDIA)
    if [ "$MULTI_MONITOR" = "true" ] && [ "$HAS_NVIDIA" = "true" ]; then
        echo "   Applying KWin DRM fix..."
        if ! grep -q "KWIN_DRM_NO_DIRECT_SCANOUT=1" /etc/environment 2>/dev/null; then
            run_or_show "echo 'KWIN_DRM_NO_DIRECT_SCANOUT=1' | sudo tee -a /etc/environment"
            log_applied "KWIN_DRM_NO_DIRECT_SCANOUT=1 (framebuffer fix)"
        else
            log_info "KWIN_DRM_NO_DIRECT_SCANOUT=1 already set"
        fi
    else
        log_skipped "KWin DRM fix (not multi-monitor + NVIDIA)"
    fi
    
    # PowerDevil DDC disable (hybrid GPU)
    if [ "$HYBRID_GPU" = "intel-nvidia" ]; then
        echo "   Applying DDC fix..."
        mkdir -p ~/.config/environment.d
        if [ ! -f ~/.config/environment.d/kwin-fixes.conf ] || ! grep -q "POWERDEVIL_NO_DDCUTIL=1" ~/.config/environment.d/kwin-fixes.conf 2>/dev/null; then
            run_or_show "cat > ~/.config/environment.d/kwin-fixes.conf << 'EOF'
# Disable DDC brightness control - prevents display crashes on hybrid GPU
# Crash signature: org_kde_powerdevil \"No Display_Ref found for i2c bus\"
POWERDEVIL_NO_DDCUTIL=1
EOF"
            log_applied "POWERDEVIL_NO_DDCUTIL=1 (DDC crash fix)"
        else
            log_info "POWERDEVIL_NO_DDCUTIL=1 already set"
        fi
    else
        log_skipped "DDC fix (not hybrid GPU)"
    fi
    
    # KWin blur disable (performance)
    echo "   Disabling KWin blur effects..."
    if [ -f ~/.config/kwinrc ]; then
        run_or_show "kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false 2>/dev/null || kwriteconfig5 --file kwinrc --group Plugins --key blurEnabled false"
        run_or_show "kwriteconfig6 --file kwinrc --group Plugins --key forceblurEnabled false 2>/dev/null || kwriteconfig5 --file kwinrc --group Plugins --key forceblurEnabled false"
        log_applied "blurEnabled=false, forceblurEnabled=false (CPU optimization)"
    else
        log_skipped "KWin config not found (KDE not running?)"
    fi
    
    echo ""
fi

# ============================================================================
# 3. POWER MANAGEMENT
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "power" || "$CATEGORY" == "Power" ]]; then
    echo -e "${BOLD}[Power] Power Management${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    # ASUS laptop profile
    if [ "$HAS_ASUSCTL" = "true" ]; then
        echo "   Configuring ASUS power profiles..."
        if command -v asusctl &>/dev/null; then
            run_or_show "asusctl profile -P Balanced"
            log_applied "ASUS profile set to Balanced"
            
            run_or_show "asusctl profile -a Balanced"
            run_or_show "asusctl profile -b Quiet"
            log_applied "AC=Balanced, Battery=Quiet defaults"
        else
            log_skipped "asusctl command not found"
        fi
    else
        log_skipped "ASUS tools not detected"
    fi
    
    # Ensure power-profiles-daemon is enabled
    echo "   Ensuring power-profiles-daemon is active..."
    run_or_show "systemctl enable --now power-profiles-daemon"
    log_applied "power-profiles-daemon enabled"
    
    echo ""
fi

# ============================================================================
# 4. MEMORY & SWAP
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "memory" || "$CATEGORY" == "Memory" ]]; then
    echo -e "${BOLD}[Memory] Swap & ZRAM Configuration${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    # Swappiness for ZRAM
    if [ "$HAS_ZRAM" = "true" ]; then
        echo "   Configuring swappiness for ZRAM..."
        if [ ! -f /etc/sysctl.d/99-swappiness.conf ] || ! grep -q "vm.swappiness=133" /etc/sysctl.d/99-swappiness.conf 2>/dev/null; then
            run_or_show "echo 'vm.swappiness=133' | sudo tee /etc/sysctl.d/99-swappiness.conf"
            run_or_show "sudo sysctl -p /etc/sysctl.d/99-swappiness.conf"
            log_applied "vm.swappiness=133 (ZRAM optimization)"
        else
            log_info "vm.swappiness=133 already set"
        fi
    else
        log_skipped "ZRAM not detected (swappiness not optimized)"
    fi
    
    # VM dirty ratios
    echo "   Configuring VM dirty writeback..."
    if [ ! -f /etc/sysctl.d/99-vm.conf ] || ! grep -q "vm.dirty_ratio" /etc/sysctl.d/99-vm.conf 2>/dev/null; then
        run_or_show "cat > /etc/sysctl.d/99-vm.conf << 'EOF'
# VM dirty writeback configuration
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.vfs_cache_pressure=100
EOF"
        run_or_show "sudo sysctl -p /etc/sysctl.d/99-vm.conf"
        log_applied "VM dirty ratios configured"
    else
        log_info "VM dirty ratios already configured"
    fi
    
    echo ""
fi

# ============================================================================
# 5. I/O SCHEDULER
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "io" || "$CATEGORY" == "storage" ]]; then
    echo -e "${BOLD}[I/O] Storage Scheduler${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    if [ "$HAS_NVME" = "true" ]; then
        echo "   Setting NVMe scheduler to kyber..."
        # Create udev rule for persistent setting
        if [ ! -f /etc/udev/rules.d/60-scheduler.rules ]; then
            run_or_show "echo 'ACTION==\"add|change\", KERNEL==\"nvme*\", ATTR{queue/scheduler}=\"kyber\"' | sudo tee /etc/udev/rules.d/60-scheduler.rules"
            log_applied "NVMe scheduler rule created (kyber)"
            log_info "Will apply on next reboot"
        else
            log_info "Scheduler rule already exists"
        fi
    else
        log_skipped "NVMe not detected"
    fi
    
    echo ""
fi

# ============================================================================
# 6. FIREWALL
# ============================================================================

if [[ "$CATEGORY" == "all" || "$CATEGORY" == "security" || "$CATEGORY" == "Security" ]]; then
    echo -e "${BOLD}[Security] Firewall Configuration${NC}"
    echo "─────────────────────────────────────────────────────────────"
    
    # Check if firewall is inactive
    if ! systemctl is-active --quiet firewalld 2>/dev/null && ! systemctl is-active --quiet ufw 2>/dev/null; then
        echo "   ⚠ Firewall is INACTIVE"
        echo ""
        echo "   Recommended: Enable firewalld with SSH access"
        echo ""
        
        if [ "$DRY_RUN" = false ]; then
            read -p "Enable firewalld now? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                run_or_show "sudo systemctl enable --now firewalld"
                
                # Ask about SSH
                read -p "Allow SSH through firewall? [y/N] " -n 1 -r
                echo ""
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    run_or_show "sudo firewall-cmd --add-service=ssh --permanent"
                    run_or_show "sudo firewall-cmd --reload"
                fi
                
                log_applied "Firewall enabled"
            else
                log_skipped "Firewall not enabled (user choice)"
            fi
        else
            log_info "[DRY-RUN] Would prompt to enable firewall"
        fi
    else
        log_info "Firewall already active"
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
echo -e "Applied:  ${GREEN}${#APPLIED[@]}${NC}"
echo -e "Skipped:  ${YELLOW}${#SKIPPED[@]}${NC}"
echo ""

if [ ${#APPLIED[@]} -gt 0 ]; then
    echo -e "${CYAN}Applied Optimizations:${NC}"
    for opt in "${APPLIED[@]}"; do
        echo "   • $opt"
    done
    echo ""
fi

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo -e "${YELLOW}Skipped (not applicable):${NC}"
    for opt in "${SKIPPED[@]}"; do
        echo "   • $opt"
    done
    echo ""
fi

# Check if GRUB was modified
if grep -q "nvidia_drm\|amdgpu\|i915.enable_psr" /etc/default/grub 2>/dev/null; then
    echo -e "${YELLOW}⚠ GRUB was modified. Run 'sudo update-grub' and reboot for changes.${NC}"
    echo ""
fi

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}=== DRY RUN COMPLETE - No changes were made ===${NC}"
fi

echo -e "${GREEN}✓ Optimization complete${NC}"
