#!/bin/bash

# ============================================
# INTERACTIVE SYSTEM HEALTH CHECK
# Live analysis with fix options
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Track issues
declare -a ISSUES
declare -a FIXES

echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}      SYSTEM HEALTH CHECK${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""

# ============================================
# 1. TEMPERATURES
# ============================================
echo -e "${CYAN}[1/10] Temperatures${NC}"
echo "─────────────────────"

if command -v sensors &>/dev/null; then
    # CPU temp
    CPU_TEMP=$(sensors 2>/dev/null | grep -i "package\|tctl" | grep -oP '\+\d+\.\d+' | head -1 | tr -d '+')
    if [ -n "$CPU_TEMP" ]; then
        TEMP_INT=${CPU_TEMP%.*}
        if [ "$TEMP_INT" -gt 85 ]; then
            echo -e "CPU: ${RED}${CPU_TEMP}°C CRITICAL${NC}"
            ISSUES+=("CPU temperature critical: ${CPU_TEMP}°C")
            FIXES+=("Clean cooling vents, use cooling pad, check thermal paste")
        elif [ "$TEMP_INT" -gt 70 ]; then
            echo -e "CPU: ${YELLOW}${CPU_TEMP}°C (warm)${NC}"
        else
            echo -e "CPU: ${GREEN}${CPU_TEMP}°C${NC}"
        fi
    fi

    # GPU temp
    if command -v nvidia-smi &>/dev/null; then
        GPU_TEMP=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null)
        if [ -n "$GPU_TEMP" ]; then
            if [ "$GPU_TEMP" -gt 80 ]; then
                echo -e "GPU: ${RED}${GPU_TEMP}°C CRITICAL${NC}"
            elif [ "$GPU_TEMP" -gt 65 ]; then
                echo -e "GPU: ${YELLOW}${GPU_TEMP}°C (warm)${NC}"
            else
                echo -e "GPU: ${GREEN}${GPU_TEMP}°C${NC}"
            fi
        fi
    fi
else
    echo -e "${YELLOW}sensors not installed${NC}"
fi
echo ""

# ============================================
# 2. CPU PERFORMANCE
# ============================================
echo -e "${CYAN}[2/10] CPU Performance${NC}"
echo "─────────────────────"

GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)
DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null)

echo "Driver: $DRIVER"
echo "Governor: $GOVERNOR"
echo "EPP: $EPP"

# Power profile
if command -v asusctl &>/dev/null; then
    PROFILE=$(asusctl profile -p 2>/dev/null | grep "Active" | awk '{print $NF}')
    if [ "$PROFILE" = "Quiet" ]; then
        echo -e "Profile: ${YELLOW}$PROFILE (may feel slow)${NC}"
        ISSUES+=("Power profile is Quiet - system may feel slow")
        FIXES+=("asusctl profile -P Balanced")
    else
        echo -e "Profile: ${GREEN}$PROFILE${NC}"
    fi
fi
echo ""

# ============================================
# 3. GPU STATUS
# ============================================
echo -e "${CYAN}[3/10] GPU Status${NC}"
echo "─────────────────────"

if command -v nvidia-smi &>/dev/null; then
    PSTATE=$(nvidia-smi --query-gpu=pstate --format=csv,noheader 2>/dev/null | tr -d ' ')
    POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader 2>/dev/null | tr -d ' ')
    UTIL=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader 2>/dev/null | tr -d ' ')

    echo "Power: $POWER"
    echo "Utilization: $UTIL"

    if [ "$PSTATE" = "P0" ] || [ "$PSTATE" = "P2" ]; then
        echo -e "State: ${YELLOW}$PSTATE (active)${NC}"
        # Check if power is high
        POWER_NUM=$(echo "$POWER" | grep -oP '\d+' | head -1)
        if [ -n "$POWER_NUM" ] && [ "$POWER_NUM" -gt 40 ]; then
            ISSUES+=("GPU drawing ${POWER} at idle (state $PSTATE)")
            FIXES+=("./scripts/restore-frozen-config.sh")
        fi
    else
        echo -e "State: ${GREEN}$PSTATE (idle)${NC}"
    fi
else
    echo "NVIDIA driver not detected"
fi
echo ""

# ============================================
# 4. MEMORY
# ============================================
echo -e "${CYAN}[4/10] Memory${NC}"
echo "─────────────────────"

MEM_TOTAL=$(free -h | grep Mem | awk '{print $2}')
MEM_USED=$(free -h | grep Mem | awk '{print $3}')
MEM_PERCENT=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100}')

if [ "$MEM_PERCENT" -gt 90 ]; then
    echo -e "RAM: ${RED}$MEM_USED / $MEM_TOTAL (${MEM_PERCENT}%) CRITICAL${NC}"
    ISSUES+=("Memory usage critical: ${MEM_PERCENT}%")
    FIXES+=("Close unused applications")
elif [ "$MEM_PERCENT" -gt 80 ]; then
    echo -e "RAM: ${YELLOW}$MEM_USED / $MEM_TOTAL (${MEM_PERCENT}%)${NC}"
else
    echo -e "RAM: ${GREEN}$MEM_USED / $MEM_TOTAL (${MEM_PERCENT}%)${NC}"
fi

# Swap
SWAP_USED=$(free -h | grep Swap | awk '{print $3}')
SWAP_TOTAL=$(free -h | grep Swap | awk '{print $2}')
echo "Swap: $SWAP_USED / $SWAP_TOTAL"
echo ""

# ============================================
# 5. DISK USAGE
# ============================================
echo -e "${CYAN}[5/10] Disk Usage${NC}"
echo "─────────────────────"

DISK_PERCENT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
DISK_USED=$(df -h / | tail -1 | awk '{print $3}')
DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')

if [ "$DISK_PERCENT" -gt 90 ]; then
    echo -e "Root: ${RED}$DISK_USED / $DISK_TOTAL (${DISK_PERCENT}%) CRITICAL${NC}"
    ISSUES+=("Disk usage critical: ${DISK_PERCENT}%")
    FIXES+=("sudo paccache -rk2")
elif [ "$DISK_PERCENT" -gt 80 ]; then
    echo -e "Root: ${YELLOW}$DISK_USED / $DISK_TOTAL (${DISK_PERCENT}%)${NC}"
else
    echo -e "Root: ${GREEN}$DISK_USED / $DISK_TOTAL (${DISK_PERCENT}%)${NC}"
fi

# Package cache
CACHE_SIZE=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
CACHE_MB=$(du -sm /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
if [ -n "$CACHE_MB" ] && [ "$CACHE_MB" -gt 10000 ]; then
    echo -e "Cache: ${YELLOW}$CACHE_SIZE (large)${NC}"
    ISSUES+=("Package cache is ${CACHE_SIZE}")
    FIXES+=("sudo paccache -rk2")
else
    echo "Cache: $CACHE_SIZE"
fi
echo ""

# ============================================
# 6. KWIN & DESKTOP
# ============================================
echo -e "${CYAN}[6/10] KWin & Desktop${NC}"
echo "─────────────────────"

KWIN_CPU=$(ps aux | grep "kwin_wayland" | grep -v grep | awk '{print $3}' | head -1)
if [ -n "$KWIN_CPU" ]; then
    KWIN_INT=${KWIN_CPU%.*}
    if [ "$KWIN_INT" -gt 50 ]; then
        echo -e "KWin CPU: ${RED}${KWIN_CPU}% HIGH${NC}"
        ISSUES+=("KWin using ${KWIN_CPU}% CPU")
        FIXES+=("./scripts/restore-frozen-config.sh")
    elif [ "$KWIN_INT" -gt 30 ]; then
        echo -e "KWin CPU: ${YELLOW}${KWIN_CPU}%${NC}"
    else
        echo -e "KWin CPU: ${GREEN}${KWIN_CPU}%${NC}"
    fi
fi

# Check blur
if [ -f "$HOME/.config/kwinrc" ]; then
    BLUR=$(grep 'blurEnabled=true' "$HOME/.config/kwinrc" 2>/dev/null)
    FORCEBLUR=$(grep 'forceblurEnabled=true' "$HOME/.config/kwinrc" 2>/dev/null)
    if [ -n "$BLUR" ] || [ -n "$FORCEBLUR" ]; then
        echo -e "Blur: ${YELLOW}enabled (high CPU)${NC}"
        ISSUES+=("Blur effects enabled (causes high CPU)")
        FIXES+=("Disable in System Settings > Desktop Effects")
    else
        echo -e "Blur: ${GREEN}disabled${NC}"
    fi
fi
echo ""

# ============================================
# 7. SERVICES
# ============================================
echo -e "${CYAN}[7/10] Services${NC}"
echo "─────────────────────"

for svc in power-profiles-daemon asusd ananicy-cpp; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        echo -e "$svc: ${GREEN}active${NC}"
    else
        echo -e "$svc: ${YELLOW}$STATUS${NC}"
    fi
done

# Failed services
FAILED=$(systemctl --failed --no-pager 2>/dev/null | grep -c "failed")
if [ "$FAILED" -gt 0 ]; then
    echo -e "Failed: ${RED}$FAILED services${NC}"
    ISSUES+=("$FAILED failed services")
    FIXES+=("systemctl --failed")
else
    echo -e "Failed: ${GREEN}none${NC}"
fi
echo ""

# ============================================
# 8. PACKAGES
# ============================================
echo -e "${CYAN}[8/10] Packages${NC}"
echo "─────────────────────"

ORPHANS=$(pacman -Qdt 2>/dev/null | wc -l)
TOTAL=$(pacman -Q 2>/dev/null | wc -l)

echo "Installed: $TOTAL"
if [ "$ORPHANS" -gt 0 ]; then
    echo -e "Orphans: ${YELLOW}$ORPHANS${NC}"
    ISSUES+=("$ORPHANS orphan packages")
    FIXES+=("sudo pacman -Rns \$(pacman -Qdtq)")
else
    echo -e "Orphans: ${GREEN}0${NC}"
fi
echo ""

# ============================================
# 9. FILESYSTEM
# ============================================
echo -e "${CYAN}[9/10] Filesystem${NC}"
echo "─────────────────────"

if mount | grep -q btrfs; then
    BTRFS_ERRORS=$(sudo btrfs device stats / 2>/dev/null | grep -v " 0$" | wc -l)
    if [ "$BTRFS_ERRORS" -gt 0 ]; then
        echo -e "Btrfs: ${RED}$BTRFS_ERRORS errors found!${NC}"
        ISSUES+=("Btrfs filesystem has errors")
        FIXES+=("sudo btrfs scrub start /")
    else
        echo -e "Btrfs: ${GREEN}healthy${NC}"
    fi
else
    echo "No btrfs detected"
fi
echo ""

# ============================================
# 10. ERRORS (This Boot)
# ============================================
echo -e "${CYAN}[10/10] Errors${NC}"
echo "─────────────────────"

CRITICAL=$(journalctl -b -p 0..2 --no-pager 2>/dev/null | wc -l)
ERRORS=$(journalctl -b -p 3 --no-pager 2>/dev/null | wc -l)

if [ "$CRITICAL" -gt 10 ]; then
    echo -e "Critical: ${RED}$CRITICAL${NC}"
    ISSUES+=("$CRITICAL critical messages in journal this boot")
    FIXES+=("journalctl -b -p 0..2 --no-pager")
elif [ "$CRITICAL" -gt 0 ]; then
    echo -e "Critical: ${YELLOW}$CRITICAL${NC}"
else
    echo -e "Critical: ${GREEN}0${NC}"
fi

if [ "$ERRORS" -gt 50 ]; then
    echo -e "Errors: ${RED}$ERRORS${NC} (check: journalctl -b -p err)"
    ISSUES+=("$ERRORS error messages in journal this boot")
    FIXES+=("journalctl -b -p err --no-pager | tail -50")
elif [ "$ERRORS" -gt 20 ]; then
    echo -e "Errors: ${YELLOW}$ERRORS${NC} (check: journalctl -b -p err)"
else
    echo "Errors: $ERRORS (check: journalctl -b -p err)"
fi
echo ""

# ============================================
# SUMMARY & FIX OPTIONS
# ============================================
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}      SUMMARY${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ No issues detected. System is healthy!${NC}"
    echo ""
    exit 0
fi

echo -e "${YELLOW}${BOLD}Found ${#ISSUES[@]} issue(s):${NC}"
echo ""

for i in "${!ISSUES[@]}"; do
    echo -e "${YELLOW}$((i+1)). ${ISSUES[$i]}${NC}"
    echo -e "   Fix: ${CYAN}${FIXES[$i]}${NC}"
    echo ""
done

# Ask to fix
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""
read -p "Fix issues now? [y/N]: " REPLY
echo ""

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
    echo -e "${BOLD}Applying fixes...${NC}"
    echo ""

    for i in "${!FIXES[@]}"; do
        FIX="${FIXES[$i]}"
        echo -e "${CYAN}[$((i+1))/${#FIXES[@]}] ${ISSUES[$i]}${NC}"
        echo "Command: $FIX"

        # Skip informational fixes
        if [[ "$FIX" == *"System Settings"* ]] || [[ "$FIX" == *"Close unused"* ]] || [[ "$FIX" == *"Clean cooling"* ]]; then
            echo -e "${YELLOW}→ Manual action required${NC}"
            echo ""
            continue
        fi

        read -p "Run this fix? [y/N]: " RUN_FIX
        if [[ "$RUN_FIX" =~ ^[Yy]$ ]]; then
            echo "Running: $FIX"
            eval "$FIX"
            echo -e "${GREEN}✓ Done${NC}"
        else
            echo "Skipped"
        fi
        echo ""
    done

    echo -e "${GREEN}${BOLD}Fixes complete!${NC}"
    echo ""
    echo "Run 'check' again to verify."
else
    echo "No changes made."
fi
