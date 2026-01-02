#!/bin/bash

# ============================================
# INTERACTIVE SYSTEM HEALTH CHECK
# Live analysis with fix options
# Usage:
#   check           # Quick check (10 areas)
#   check --deep    # Deep analysis (18 areas)
# ============================================

DEEP_MODE=false
[[ "$1" == "--deep" || "$1" == "-d" ]] && DEEP_MODE=true

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
if [ "$DEEP_MODE" = true ]; then
    echo -e "${BOLD}      DEEP SYSTEM HEALTH CHECK${NC}"
    TOTAL_CHECKS=18
else
    echo -e "${BOLD}      SYSTEM HEALTH CHECK${NC}"
    TOTAL_CHECKS=10
fi
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""

# ============================================
# 1. TEMPERATURES
# ============================================
echo -e "${CYAN}[1/$TOTAL_CHECKS] Temperatures${NC}"
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
echo -e "${CYAN}[2/$TOTAL_CHECKS] CPU Performance${NC}"
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
echo -e "${CYAN}[3/$TOTAL_CHECKS] GPU Status${NC}"
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
echo -e "${CYAN}[4/$TOTAL_CHECKS] Memory${NC}"
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
echo -e "${CYAN}[5/$TOTAL_CHECKS] Disk Usage${NC}"
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
echo -e "${CYAN}[6/$TOTAL_CHECKS] KWin & Desktop${NC}"
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
echo -e "${CYAN}[7/$TOTAL_CHECKS] Services${NC}"
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
echo -e "${CYAN}[8/$TOTAL_CHECKS] Packages${NC}"
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
echo -e "${CYAN}[9/$TOTAL_CHECKS] Filesystem${NC}"
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
echo -e "${CYAN}[10/$TOTAL_CHECKS] Errors${NC}"
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
# DEEP CHECKS (11-18)
# ============================================
if [ "$DEEP_MODE" = true ]; then

# ============================================
# 11. DISK SMART HEALTH
# ============================================
echo -e "${CYAN}[11/$TOTAL_CHECKS] Disk SMART Health${NC}"
echo "─────────────────────"

if command -v smartctl &>/dev/null; then
    for disk in /dev/nvme0n1 /dev/sda /dev/sdb; do
        if [ -b "$disk" ]; then
            DISK_NAME=$(basename "$disk")
            HEALTH=$(sudo smartctl -H "$disk" 2>/dev/null | grep -i "overall\|result" | head -1)
            if echo "$HEALTH" | grep -qi "passed\|ok"; then
                echo -e "$DISK_NAME: ${GREEN}PASSED${NC}"
            elif [ -n "$HEALTH" ]; then
                echo -e "$DISK_NAME: ${RED}$HEALTH${NC}"
                ISSUES+=("Disk $DISK_NAME SMART health warning")
                FIXES+=("sudo smartctl -a $disk")
            fi
        fi
    done
else
    echo -e "${YELLOW}smartctl not installed (smartmontools)${NC}"
fi
echo ""

# ============================================
# 12. NETWORK STATUS
# ============================================
echo -e "${CYAN}[12/$TOTAL_CHECKS] Network Status${NC}"
echo "─────────────────────"

# Check connectivity
if ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo -e "Internet: ${GREEN}connected${NC}"
else
    echo -e "Internet: ${RED}no connection${NC}"
    ISSUES+=("No internet connection")
    FIXES+=("nmcli device status")
fi

# DNS
if ping -c 1 -W 2 google.com &>/dev/null; then
    echo -e "DNS: ${GREEN}working${NC}"
else
    echo -e "DNS: ${YELLOW}not resolving${NC}"
fi

# Active connections
ACTIVE_CONN=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null | head -3)
if [ -n "$ACTIVE_CONN" ]; then
    echo "Active: $(echo "$ACTIVE_CONN" | cut -d: -f1 | tr '\n' ', ' | sed 's/,$//')"
fi
echo ""

# ============================================
# 13. SECURITY CHECK
# ============================================
echo -e "${CYAN}[13/$TOTAL_CHECKS] Security${NC}"
echo "─────────────────────"

# Firewall
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1)
    if echo "$UFW_STATUS" | grep -q "active"; then
        echo -e "Firewall (ufw): ${GREEN}active${NC}"
    else
        echo -e "Firewall (ufw): ${YELLOW}inactive${NC}"
        ISSUES+=("UFW firewall is inactive")
        FIXES+=("sudo ufw enable")
    fi
elif command -v firewall-cmd &>/dev/null; then
    if firewall-cmd --state &>/dev/null; then
        echo -e "Firewall (firewalld): ${GREEN}active${NC}"
    else
        echo -e "Firewall (firewalld): ${YELLOW}inactive${NC}"
    fi
else
    echo "Firewall: not detected"
fi

# SSH
if systemctl is-active sshd &>/dev/null; then
    echo -e "SSH: ${YELLOW}running (port open)${NC}"
else
    echo -e "SSH: ${GREEN}not running${NC}"
fi

# Failed login attempts
FAILED_LOGINS=$(journalctl -b _SYSTEMD_UNIT=sshd.service 2>/dev/null | grep -c "Failed password" || echo 0)
if [ "$FAILED_LOGINS" -gt 10 ]; then
    echo -e "Failed SSH logins: ${RED}$FAILED_LOGINS${NC}"
    ISSUES+=("$FAILED_LOGINS failed SSH login attempts this boot")
    FIXES+=("journalctl -b _SYSTEMD_UNIT=sshd.service | grep 'Failed'")
elif [ "$FAILED_LOGINS" -gt 0 ]; then
    echo "Failed SSH logins: $FAILED_LOGINS"
fi
echo ""

# ============================================
# 14. BOOT TIME ANALYSIS
# ============================================
echo -e "${CYAN}[14/$TOTAL_CHECKS] Boot Time${NC}"
echo "─────────────────────"

BOOT_TIME=$(systemd-analyze 2>/dev/null | grep "Startup finished" | grep -oP '\d+\.\d+s$' | head -1)
if [ -n "$BOOT_TIME" ]; then
    BOOT_SEC=$(echo "$BOOT_TIME" | tr -d 's')
    BOOT_INT=${BOOT_SEC%.*}
    if [ "$BOOT_INT" -gt 60 ]; then
        echo -e "Boot time: ${RED}$BOOT_TIME (slow)${NC}"
        ISSUES+=("Slow boot time: $BOOT_TIME")
        FIXES+=("systemd-analyze blame | head -10")
    elif [ "$BOOT_INT" -gt 30 ]; then
        echo -e "Boot time: ${YELLOW}$BOOT_TIME${NC}"
    else
        echo -e "Boot time: ${GREEN}$BOOT_TIME${NC}"
    fi
fi

# Slowest services
echo "Slowest services:"
systemd-analyze blame 2>/dev/null | head -3 | sed 's/^/  /'
echo ""

# ============================================
# 15. ZOMBIE & STUCK PROCESSES
# ============================================
echo -e "${CYAN}[15/$TOTAL_CHECKS] Zombie Processes${NC}"
echo "─────────────────────"

ZOMBIES=$(ps aux | awk '$8=="Z" {print $0}' | wc -l)
if [ "$ZOMBIES" -gt 0 ]; then
    echo -e "Zombies: ${RED}$ZOMBIES found${NC}"
    ps aux | awk '$8=="Z" {print "  "$11}' | head -5
    ISSUES+=("$ZOMBIES zombie processes")
    FIXES+=("ps aux | awk '\$8==\"Z\"'")
else
    echo -e "Zombies: ${GREEN}none${NC}"
fi

# High CPU processes
HIGH_CPU=$(ps aux --sort=-%cpu | awk 'NR>1 && $3>50 {print $11, $3"%"}' | head -3)
if [ -n "$HIGH_CPU" ]; then
    echo -e "High CPU: ${YELLOW}"
    echo "$HIGH_CPU" | sed 's/^/  /'
    echo -e "${NC}"
fi
echo ""

# ============================================
# 16. KERNEL MESSAGES
# ============================================
echo -e "${CYAN}[16/$TOTAL_CHECKS] Kernel Messages${NC}"
echo "─────────────────────"

DMESG_ERRORS=$(dmesg --level=err,crit,alert,emerg 2>/dev/null | wc -l)
if [ "$DMESG_ERRORS" -gt 20 ]; then
    echo -e "Kernel errors: ${RED}$DMESG_ERRORS${NC}"
    ISSUES+=("$DMESG_ERRORS kernel errors in dmesg")
    FIXES+=("dmesg --level=err,crit | tail -20")
elif [ "$DMESG_ERRORS" -gt 5 ]; then
    echo -e "Kernel errors: ${YELLOW}$DMESG_ERRORS${NC}"
else
    echo -e "Kernel errors: ${GREEN}$DMESG_ERRORS${NC}"
fi

# Recent hardware errors
HW_ERRORS=$(dmesg 2>/dev/null | grep -i "hardware error\|mce:\|pcie.*error" | wc -l)
if [ "$HW_ERRORS" -gt 0 ]; then
    echo -e "Hardware errors: ${RED}$HW_ERRORS${NC}"
    ISSUES+=("$HW_ERRORS hardware errors in dmesg")
    FIXES+=("dmesg | grep -i 'hardware error\\|mce:\\|pcie.*error'")
fi
echo ""

# ============================================
# 17. SYSTEM LOAD
# ============================================
echo -e "${CYAN}[17/$TOTAL_CHECKS] System Load${NC}"
echo "─────────────────────"

LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
LOAD_1=$(echo "$LOAD" | awk '{print $1}')
CPU_COUNT=$(nproc)
LOAD_INT=${LOAD_1%.*}

echo "Load avg (1/5/15 min): $LOAD"
echo "CPU cores: $CPU_COUNT"

if [ "$LOAD_INT" -gt "$CPU_COUNT" ]; then
    echo -e "Status: ${RED}overloaded${NC}"
    ISSUES+=("System load ($LOAD_1) exceeds CPU count ($CPU_COUNT)")
    FIXES+=("top -bn1 | head -20")
elif [ "$LOAD_INT" -gt $((CPU_COUNT / 2)) ]; then
    echo -e "Status: ${YELLOW}moderate${NC}"
else
    echo -e "Status: ${GREEN}low${NC}"
fi
echo ""

# ============================================
# 18. OPEN FILES & CONNECTIONS
# ============================================
echo -e "${CYAN}[18/$TOTAL_CHECKS] Open Files & Connections${NC}"
echo "─────────────────────"

# Open files
OPEN_FILES=$(cat /proc/sys/fs/file-nr | awk '{print $1}')
MAX_FILES=$(cat /proc/sys/fs/file-max)
FILE_PERCENT=$((OPEN_FILES * 100 / MAX_FILES))

echo "Open files: $OPEN_FILES / $MAX_FILES ($FILE_PERCENT%)"
if [ "$FILE_PERCENT" -gt 80 ]; then
    echo -e "Status: ${RED}high${NC}"
    ISSUES+=("Open files at $FILE_PERCENT% of limit")
    FIXES+=("lsof | wc -l")
fi

# Network connections
ESTABLISHED=$(ss -t state established 2>/dev/null | wc -l)
LISTENING=$(ss -tln 2>/dev/null | wc -l)
echo "TCP established: $ESTABLISHED"
echo "TCP listening: $LISTENING"
echo ""

fi
# END DEEP CHECKS

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
