#!/bin/bash
# ============================================================================
# Hardware Detection Script for Garuda Restore Kit
# ============================================================================
# Detects hardware and outputs a structured profile for conditional
# optimization application. Used by restore.sh and apply-optimizations.sh
#
# Usage:
#   ./detect-hardware.sh              # JSON output
#   ./detect-hardware.sh --summary    # Human-readable summary
#   ./detect-hardware.sh --check GPU  # Check specific component
# ============================================================================

set -e

# Output mode
MODE="json"
[[ "$1" == "--summary" || "$1" == "-s" ]] && MODE="summary"
[[ "$1" == "--check" || "$1" == "-c" ]] && MODE="check" && CHECK_COMPONENT="$2"

# ============================================================================
# DETECTION FUNCTIONS
# ============================================================================

detect_machine_type() {
    local chassis_type
    chassis_type=$(systemd-detect-virt --chassis 2>/dev/null || echo "unknown")
    
    case "$chassis_type" in
        laptop|notebook)
            MACHINE_TYPE="laptop"
            ;;
        desktop|tower|mini-tower|all-in-one)
            MACHINE_TYPE="desktop"
            ;;
        vm|container)
            MACHINE_TYPE="virtual"
            ;;
        *)
            MACHINE_TYPE="unknown"
            ;;
    esac
}

detect_vendor_model() {
    # dmidecode requires sudo, so try with sudo first, then fall back
    VENDOR=$(sudo dmidecode -s system-manufacturer 2>/dev/null | tr -d '\n' || dmidecode -s system-manufacturer 2>/dev/null | tr -d '\n' || echo "Unknown")
    MODEL=$(sudo dmidecode -s system-product-name 2>/dev/null | tr -d '\n' || dmidecode -s system-product-name 2>/dev/null | tr -d '\n' || echo "Unknown")
    
    # Clean up common vendor names
    if [ -n "$VENDOR" ] && [ "$VENDOR" != "Unknown" ]; then
        VENDOR=$(echo "$VENDOR" | sed -e 's/Co\., Ltd\.//g' -e 's/Inc\.//g' -e 's/LLC//g' -e 's/Ltd\.//g' | xargs)
    fi
    
    # If still empty, mark as unknown
    [ -z "$VENDOR" ] && VENDOR="Unknown"
    [ -z "$MODEL" ] && MODEL="Unknown"
}

detect_cpu() {
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
    CPU_CORES=$(nproc)
    CPU_THREADS=$(grep -c "^processor" /proc/cpuinfo)
}

detect_gpu() {
    # Detect all GPUs
    HAS_NVIDIA=false
    HAS_AMD_GPU=false
    HAS_INTEL_IGPU=false
    HAS_INTEL_DISCRETE=false
    GPU_COUNT=0
    
    # NVIDIA detection
    if lspci 2>/dev/null | grep -qi "nvidia"; then
        HAS_NVIDIA=true
        GPU_COUNT=$((GPU_COUNT + 1))
        NVIDIA_MODEL=$(lspci | grep -i "nvidia" | head -1 | cut -d':' -f3 | xargs)
    fi
    
    # AMD GPU detection
    if lspci 2>/dev/null | grep -qi "amd\|ati"; then
        HAS_AMD_GPU=true
        GPU_COUNT=$((GPU_COUNT + 1))
        AMD_MODEL=$(lspci | grep -i "amd\|ati" | head -1 | cut -d':' -f3 | xargs)
    fi
    
    # Intel GPU detection
    if lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*compatible"; then
        # Determine if integrated or discrete
        if echo "$MODEL" | grep -qi "ultrabook\|laptop\|notebook"; then
            HAS_INTEL_IGPU=true
        else
            # Check if it's Iris Xe or similar (could be in desktop)
            HAS_INTEL_IGPU=true
        fi
        GPU_COUNT=$((GPU_COUNT + 1))
        INTEL_MODEL=$(lspci | grep -i "intel" | grep -i "vga\|display\|graphics" | head -1 | cut -d':' -f3 | xargs)
    fi
    
    # Determine hybrid GPU configuration
    HYBRID_GPU="none"
    if [ "$HAS_NVIDIA" = true ] && [ "$HAS_INTEL_IGPU" = true ]; then
        HYBRID_GPU="intel-nvidia"
    elif [ "$HAS_AMD_GPU" = true ] && [ "$HAS_INTEL_IGPU" = true ]; then
        HYBRID_GPU="intel-amd"
    elif [ "$HAS_AMD_GPU" = true ] && [ "$HAS_NVIDIA" = true ]; then
        HYBRID_GPU="amd-nvidia"  # Rare, but exists (e.g., some ASUS laptops)
    fi
}

detect_display() {
    DISPLAY_COUNT=0
    INTERNAL_DISPLAY=false
    EXTERNAL_DISPLAYS=0
    HAS_HIGH_DPI=false

    # Detect connected displays
    for connector in /sys/class/drm/card*/card*-*; do
        if [ -f "$connector/status" ] && grep -q "connected" "$connector/status" 2>/dev/null; then
            DISPLAY_COUNT=$((DISPLAY_COUNT + 1))
            CONNECTOR_NAME=$(basename "$connector")

            # Check if internal (eDP) or external
            if [[ "$CONNECTOR_NAME" == *"eDP"* ]]; then
                INTERNAL_DISPLAY=true
            else
                EXTERNAL_DISPLAYS=$((EXTERNAL_DISPLAYS + 1))
            fi

            # Check resolution for high-DPI
            if [ -f "$connector/modes" ]; then
                BEST_MODE=$(head -1 "$connector/modes")
                WIDTH=$(echo "$BEST_MODE" | cut -d'x' -f1)
                if [ "$WIDTH" -ge 2560 ] 2>/dev/null; then
                    HAS_HIGH_DPI=true
                fi
            fi
        fi
    done

    # Multi-monitor setup detection
    if [ "$DISPLAY_COUNT" -gt 1 ]; then
        MULTI_MONITOR=true
    else
        MULTI_MONITOR=false
    fi
}

detect_storage() {
    HAS_NVME=false
    NVME_COUNT=0
    HAS_SATA_SSD=false
    HAS_HDD=false
    
    # Check for NVMe drives
    if ls /dev/nvme* 2>/dev/null | head -1 > /dev/null; then
        HAS_NVME=true
        NVME_COUNT=$(ls /dev/nvme* 2>/dev/null | wc -l)
    fi
    
    # Check for SATA SSD
    for disk in /dev/sd[a-z]; do
        if [ -b "$disk" ]; then
            DISK_TYPE=$(cat "/sys/block/$(basename "$disk")/queue/rotational" 2>/dev/null || echo "unknown")
            if [ "$DISK_TYPE" = "0" ]; then
                HAS_SATA_SSD=true
            else
                HAS_HDD=true
            fi
        fi
    done
}

detect_ram() {
    RAM_TOTAL_KB=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
    RAM_TOTAL_GB=$((RAM_TOTAL_KB / 1024 / 1024))
    
    # Determine if low RAM (< 8GB), standard (8-16GB), or high (32GB+)
    if [ "$RAM_TOTAL_GB" -lt 8 ]; then
        RAM_CATEGORY="low"
    elif [ "$RAM_TOTAL_GB" -lt 24 ]; then
        RAM_CATEGORY="standard"
    else
        RAM_CATEGORY="high"
    fi
}

detect_peripherals() {
    # ASUS-specific tools
    HAS_ASUSCTL=false
    HAS_SUPERGFXCTL=false
    if command -v asusctl &>/dev/null; then
        if systemctl is-active --quiet asusd 2>/dev/null; then
            HAS_ASUSCTL=true
        fi
    fi
    
    if command -v supergfxctl &>/dev/null; then
        if systemctl is-active --quiet supergfxd 2>/dev/null; then
            HAS_SUPERGFXCTL=true
        fi
    fi
    
    # Fingerprint reader
    HAS_FINGERPRINT=false
    if [ -f /etc/fprintd.conf ] || systemctl is-active --quiet fprintd 2>/dev/null; then
        HAS_FINGERPRINT=true
    fi
    
    # Bluetooth
    HAS_BLUETOOTH=false
    if systemctl is-active --quiet bluetooth 2>/dev/null; then
        HAS_BLUETOOTH=true
    fi
    
    # Firewall
    HAS_FIREWALL=false
    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld 2>/dev/null; then
        HAS_FIREWALL=true
    elif command -v ufw &>/dev/null && systemctl is-active --quiet ufw 2>/dev/null; then
        HAS_FIREWALL=true
    fi
}

detect_current_settings() {
    # CPU governor
    CPU_GOVERNOR=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")
    CPU_EPP=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "unknown")
    CPU_DRIVER=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo "unknown")
    
    # I/O scheduler (first NVMe or SATA)
    for disk in /dev/nvme0n1 /dev/sda; do
        if [ -b "$disk" ]; then
            DISK_NAME=$(basename "$disk")
            IO_SCHEDULER=$(cat "/sys/block/$DISK_NAME/queue/scheduler" 2>/dev/null | tr -d '[]' | xargs || echo "unknown")
            break
        fi
    done
    
    # Swappiness
    SWAPPINESS=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo "60")
    
    # ZRAM
    HAS_ZRAM=false
    if [ -b /dev/zram0 ]; then
        HAS_ZRAM=true
    fi
    
    # NVIDIA power state
    if [ "$HAS_NVIDIA" = true ] && command -v nvidia-smi &>/dev/null; then
        NVIDIA_PSTATE=$(nvidia-smi --query-gpu=pstate --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "unknown")
        NVIDIA_POWER=$(nvidia-smi --query-gpu=power.draw --format=csv,noheader 2>/dev/null | head -1 | xargs || echo "unknown")
    fi
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

output_json() {
    cat << EOF
{
  "machine": {
    "type": "$MACHINE_TYPE",
    "vendor": "$VENDOR",
    "model": "$MODEL"
  },
  "cpu": {
    "model": "$CPU_MODEL",
    "cores": $CPU_CORES,
    "threads": $CPU_THREADS
  },
  "gpu": {
    "count": $GPU_COUNT,
    "nvidia": $HAS_NVIDIA,
    "amd": $HAS_AMD_GPU,
    "intel": $HAS_INTEL_IGPU,
    "hybrid": "$HYBRID_GPU"
  },
  "display": {
    "count": $DISPLAY_COUNT,
    "internal": $INTERNAL_DISPLAY,
    "external_count": $EXTERNAL_DISPLAYS,
    "high_dpi": $HAS_HIGH_DPI,
    "multi_monitor": $MULTI_MONITOR
  },
  "storage": {
    "nvme": $HAS_NVME,
    "nvme_count": $NVME_COUNT,
    "sata_ssd": $HAS_SATA_SSD,
    "hdd": $HAS_HDD
  },
  "memory": {
    "total_gb": $RAM_TOTAL_GB,
    "category": "$RAM_CATEGORY"
  },
  "peripherals": {
    "asusctl": $HAS_ASUSCTL,
    "supergfxctl": $HAS_SUPERGFXCTL,
    "fingerprint": $HAS_FINGERPRINT,
    "bluetooth": $HAS_BLUETOOTH,
    "firewall": $HAS_FIREWALL
  },
  "current_settings": {
    "cpu_governor": "$CPU_GOVERNOR",
    "cpu_epp": "$CPU_EPP",
    "cpu_driver": "$CPU_DRIVER",
    "io_scheduler": "$IO_SCHEDULER",
    "swappiness": $SWAPPINESS,
    "has_zram": $HAS_ZRAM
  }
}
EOF
}

output_summary() {
    echo "═══════════════════════════════════════════════════════════"
    echo "                    HARDWARE PROFILE"
    echo "═══════════════════════════════════════════════════════════"
    echo ""
    echo "Machine:  $VENDOR $MODEL"
    echo "Type:     $MACHINE_TYPE"
    echo ""
    echo "CPU:      $CPU_MODEL"
    echo "          $CPU_CORES cores / $CPU_THREADS threads"
    echo ""
    echo "GPU:      Count: $GPU_COUNT"
    [ "$HAS_NVIDIA" = true ] && echo "          • NVIDIA: $NVIDIA_MODEL"
    [ "$HAS_AMD_GPU" = true ] && echo "          • AMD: $AMD_MODEL"
    [ "$HAS_INTEL_IGPU" = true ] && echo "          • Intel: $INTEL_MODEL"
    [ "$HYBRID_GPU" != "none" ] && echo "          → Hybrid: $HYBRID_GPU"
    echo ""
    echo "Display:  $DISPLAY_COUNT connected"
    [ "$INTERNAL_DISPLAY" = true ] && echo "          • Internal (eDP): Yes"
    echo "          • External: $EXTERNAL_DISPLAYS"
    [ "$HAS_HIGH_DPI" = true ] && echo "          • High-DPI (≥1440p): Yes"
    [ "$MULTI_MONITOR" = true ] && echo "          → Multi-monitor setup"
    echo ""
    echo "Storage:  $([ "$HAS_NVME" = true ] && echo "NVMe: $NVME_COUNT" || echo "No NVMe")"
    [ "$HAS_SATA_SSD" = true ] && echo "          • SATA SSD: Yes"
    [ "$HAS_HDD" = true ] && echo "          • HDD: Yes"
    echo ""
    echo "Memory:   ${RAM_TOTAL_GB}GB ($RAM_CATEGORY)"
    echo ""
    echo "Peripherals:"
    echo "          • asusctl: $([ "$HAS_ASUSCTL" = true ] && echo "Yes" || echo "No")"
    echo "          • supergfxctl: $([ "$HAS_SUPERGFXCTL" = true ] && echo "Yes" || echo "No")"
    echo "          • Fingerprint: $([ "$HAS_FINGERPRINT" = true ] && echo "Yes" || echo "No")"
    echo "          • Bluetooth: $([ "$HAS_BLUETOOTH" = true ] && echo "Active" || echo "Inactive")"
    echo "          • Firewall: $([ "$HAS_FIREWALL" = true ] && echo "Active" || echo "⚠ Inactive")"
    echo ""
    echo "Current Settings:"
    echo "          • CPU Governor: $CPU_GOVERNOR"
    echo "          • EPP: $CPU_EPP"
    echo "          • I/O Scheduler: $IO_SCHEDULER"
    echo "          • Swappiness: $SWAPPINESS"
    echo "          • ZRAM: $([ "$HAS_ZRAM" = true ] && echo "Active" || echo "Not configured")"
    [ "$HAS_NVIDIA" = true ] && echo "          • NVIDIA State: $NVIDIA_PSTATE, $NVIDIA_POWER"
    echo ""
    echo "═══════════════════════════════════════════════════════════"
}

output_check() {
    case "$CHECK_COMPONENT" in
        GPU|gpu)
            echo "GPU Count: $GPU_COUNT"
            echo "NVIDIA: $HAS_NVIDIA"
            echo "AMD: $HAS_AMD_GPU"
            echo "Intel: $HAS_INTEL_IGPU"
            echo "Hybrid: $HYBRID_GPU"
            [ "$HAS_NVIDIA" = true ] && echo "NVIDIA Model: $NVIDIA_MODEL"
            [ "$HAS_AMD_GPU" = true ] && echo "AMD Model: $AMD_MODEL"
            [ "$HAS_INTEL_IGPU" = true ] && echo "Intel Model: $INTEL_MODEL"
            ;;
        display|DISPLAY)
            echo "Display Count: $DISPLAY_COUNT"
            echo "Internal: $INTERNAL_DISPLAY"
            echo "External: $EXTERNAL_DISPLAYS"
            echo "High-DPI: $HAS_HIGH_DPI"
            echo "Multi-Monitor: $MULTI_MONITOR"
            ;;
        storage|STORAGE)
            echo "NVMe: $HAS_NVME ($NVME_COUNT drives)"
            echo "SATA SSD: $HAS_SATA_SSD"
            echo "HDD: $HAS_HDD"
            ;;
        memory|MEMORY|ram|RAM)
            echo "Total RAM: ${RAM_TOTAL_GB}GB"
            echo "Category: $RAM_CATEGORY"
            ;;
        *)
            echo "Unknown component: $CHECK_COMPONENT"
            echo "Valid options: GPU, display, storage, memory"
            exit 1
            ;;
    esac
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Run all detections
detect_machine_type
detect_vendor_model
detect_cpu
detect_gpu
detect_display
detect_storage
detect_ram
detect_peripherals
detect_current_settings

# Output based on mode
case "$MODE" in
    json)
        output_json
        ;;
    summary)
        output_summary
        ;;
    check)
        output_check
        ;;
esac
