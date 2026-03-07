# Hardware-Agnostic Restore Kit Architecture

## Design Philosophy

The restore kit must work on **any** Garuda Linux installation without modification. Hardware-specific settings are:
1. **Detected automatically** at runtime
2. **Applied conditionally** based on detected hardware
3. **Documented clearly** with opt-in prompts
4. **Safely skipped** when hardware doesn't match

---

## Hardware Detection Layers

### Layer 1: Machine Type Detection

```bash
# Detect laptop vs desktop
if systemd-detect-virt --chassis == "laptop"; then
    LAPTOP=true
else
    LAPTOP=false
fi

# Detect vendor (ASUS, Dell, HP, etc.)
VENDOR=$(dmidecode -s system-manufacturer)
MODEL=$(dmidecode -s system-product-name)
```

### Layer 2: GPU Detection

```bash
# Detect GPU configuration
if lspci | grep -q "NVIDIA.*VGA"; then
    HAS_NVIDIA=true
    NVIDIA_CARD=$(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader 2>/dev/null)
fi

if lspci | grep -q "Intel.*VGA\|Intel.*Display"; then
    HAS_INTEL_IGPU=true
fi

if lspci | grep -q "AMD.*VGA\|AMD.*Radeon"; then
    HAS_AMD_GPU=true
fi

# Hybrid GPU detection
if [ "$HAS_NVIDIA" = true ] && [ "$HAS_INTEL_IGPU" = true ]; then
    HYBRID_GPU="intel-nvidia"
elif [ "$HAS_AMD_GPU" = true ] && [ "$HAS_INTEL_IGPU" = true ]; then
    HYBRID_GPU="intel-amd"
else
    HYBRID_GPU="none"
fi
```

### Layer 3: Display Detection

```bash
# Detect connected displays and their properties
for connector in /sys/class/drm/card*/card*-*; do
    if [ -f "$connector/status" ] && grep -q "connected" "$connector/status"; then
        CONNECTOR_NAME=$(basename "$connector")
        # Get resolution, refresh rate, scale preference
    fi
done
```

### Layer 4: Peripheral Detection

```bash
# Detect ASUS-specific tools availability
if command -v asusctl &>/dev/null && systemctl is-active --quiet asusd; then
    HAS_ASUSCTL=true
else
    HAS_ASUSCTL=false
fi

# Detect fingerprint reader
if [ -d /etc/fprintd.conf ] || systemctl is-active --quiet fprintd; then
    HAS_FINGERPRINT=true
fi
```

---

## Conditional Settings Matrix

| Setting | Condition | Apply? | Why |
|---------|-----------|--------|-----|
| `KWIN_DRM_NO_DIRECT_SCANOUT=1` | Multi-monitor + NVIDIA | ✅ Yes | Prevents framebuffer errors |
| `POWERDEVIL_NO_DDCUTIL=1` | Hybrid GPU (intel-nvidia) | ✅ Yes | Prevents DDC I2C crashes |
| `asusctl` profile setup | `HAS_ASUSCTL=true` | ✅ Yes | ASUS laptop only |
| NVIDIA DRM modeset | `HAS_NVIDIA=true` | ✅ Yes | Required for Wayland |
| Intel VAAPI drivers | `HAS_INTEL_IGPU=true` | ✅ Yes | Hardware acceleration |
| AMD VULKAN_ICD | `HAS_AMD_GPU=true` | ✅ Yes | Vulkan compute |
| NVMe scheduler `kyber` | Has NVMe drive | ✅ Yes | Optimal for NVMe |
| ZRAM configuration | RAM < 32GB | ⚠️ Optional | More critical with less RAM |
| Swappiness 133 | Using ZRAM | ✅ Yes | ZRAM optimization |
| `nvidia_drm.fbdev=1` | ⚠️ **OPT-IN ONLY** | ❌ No | Thermal safety policy — requires `--force-fbdev` flag |

---

## Restore Script Flow

### Phase 1: Detection (Non-destructive)
```
1. Detect hardware profile
2. Display detected hardware summary
3. Show which optimizations will be applied
4. Allow user to review/modify before applying
```

### Phase 2: Base Installation (Universal)
```
1. Update system
2. Configure Chaotic-AUR
3. Install paru (AUR helper)
4. Install all packages from lists
5. Restore user configs (~/.config)
6. Restore dotfiles
7. Restore security credentials (SSH, GPG)
```

### Phase 3: Hardware-Specific Optimizations (Conditional)
```
FOR each detected hardware feature:
  IF condition matches:
    Apply optimization
    Log what was applied and why
  ELSE:
    Skip with explanation
```

### Phase 4: Validation
```
1. Verify all services running
2. Check GPU state
3. Test display configuration
4. Prompt for reboot
```

---

## Example: GPU-Specific GRUB Parameters

```bash
# Hardware-agnostic GRUB configuration
configure_grub_gpu() {
    if [ "$HAS_NVIDIA" = true ]; then
        # NVIDIA: Enable DRM modeset for Wayland
        GRUB_PARAMS="quiet loglevel=3 nvidia_drm.modeset=1"

        # NOTE: nvidia_drm.fbdev=1 is NOT auto-applied due to thermal safety policy
        # It requires explicit user opt-in via --force-fbdev flag
        # See docs/SLEEP-WAKE-ISSUES.md for thermal safety details

    elif [ "$HAS_AMD_GPU" = true ]; then
        # AMD: Enable Vulkan and compute
        GRUB_PARAMS="quiet loglevel=3 amdgpu.sg_display=0"

    elif [ "$HAS_INTEL_IGPU" = true ]; then
        # Intel: Enable VAAPI
        GRUB_PARAMS="quiet loglevel=3 i915.enable_psr=0"
    fi

    # Apply to /etc/default/grub
    sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_PARAMS\"/" /etc/default/grub
}
```

---

## Example: ASUS-Specific Tools

```bash
# Only configure asusctl if detected
if [ "$HAS_ASUSCTL" = true ]; then
    echo "ASUS laptop detected - configuring power profiles"
    
    # Set balanced as default (safe for all laptops)
    asusctl profile -P Balanced
    
    # Set AC/battery profiles (optional, user choice)
    read -p "Set aggressive charging profiles? [y/N]: " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        asusctl profile -a Balanced
        asusctl profile -b Quiet
    fi
else
    echo "ASUS tools not detected - skipping asusctl configuration"
    echo "Using power-profiles-daemon instead"
fi
```

---

## Example: Display Configuration

```bash
# Generate kwinoutputconfig.json based on detected displays
generate_kwin_output_config() {
    cat > ~/.config/kwinoutputconfig.json << 'EOF'
{
  "outputs": [
EOF

    first=true
    for connector in /sys/class/drm/card*/card*-*; do
        if [ -f "$connector/status" ] && grep -q "connected" "$connector/status"; then
            CONNECTOR_NAME=$(basename "$connector")
            
            # Get preferred resolution
            RESOLUTION=$(cat "$connector/modes" | head -1)
            WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
            HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2 | cut -d'@' -f1)
            REFRESH=$(echo "$RESOLUTION" | cut -d'@' -f2)
            
            # Calculate scale based on resolution and screen size
            SCALE=$(calculate_scale "$WIDTH" "$HEIGHT")
            
            if [ "$first" = true ]; then
                first=false
            else
                echo "," >> ~/.config/kwinoutputconfig.json
            fi
            
            cat >> ~/.config/kwinoutputconfig.json << EOF
    {
      "connectorName": "$CONNECTOR_NAME",
      "allowDdcCi": false,
      "vrrPolicy": "Never",
      "scale": $SCALE,
      "mode": { "width": $WIDTH, "height": $HEIGHT, "refreshRate": $((REFRESH * 1000)) }
    }
EOF
        fi
    done
    
    cat >> ~/.config/kwinoutputconfig.json << 'EOF'
  ]
}
EOF
}
```

---

## Documentation Requirements

Every setting applied by the restore kit must have:

1. **What**: The exact setting/value
2. **Why**: The problem it solves
3. **When**: Under what hardware conditions it applies
4. **Rollback**: How to undo it if needed

Example documentation block:

```markdown
### POWERDEVIL_NO_DDCUTIL=1

**Location:** `~/.config/environment.d/kwin-fixes.conf`

**Applied when:** Hybrid GPU detected (Intel + NVIDIA)

**Why:** DDC/CI brightness control causes display server crashes on hybrid GPU 
systems. Crash signature: `org_kde_powerdevil "No Display_Ref found for i2c bus"`.

**Safe to remove?** Yes, but may cause brightness control crashes.

**Rollback:**
```bash
rm ~/.config/environment.d/kwin-fixes.conf
# Logout and login
```
```

---

## Testing Matrix

Test the restore kit on:

| Hardware Type | Test Status | Notes |
|---------------|-------------|-------|
| ASUS + NVIDIA + Intel | ✅ Tested | Current machine |
| Dell + NVIDIA only | ⏳ Pending | Single GPU desktop |
| HP + AMD + Intel | ⏳ Pending | Hybrid AMD laptop |
| Framework + AMD | ⏳ Pending | Pure AMD laptop |
| VM (no GPU) | ⏳ Pending | Virtual machine |

---

## Migration from Old Restore Kit

The existing `restore.sh` is already mostly hardware-agnostic. Changes needed:

1. ✅ No hardcoded device paths found
2. ✅ No hardcoded connector names found
3. ⚠️ Add hardware detection phase at start
4. ⚠️ Add conditional logic for ASUS tools
5. ⚠️ Add documentation output during restore
6. ⚠️ Create rollback documentation

---

## File Structure

```
garuda-restore/
├── scripts/
│   ├── restore.sh              # Main restore (hardware-agnostic)
│   ├── backup.sh               # Backup (already agnostic)
│   ├── tools/
│   │   ├── detect-hardware.sh  # NEW: Hardware detection
│   │   ├── system-health-check.sh  # check command
│   │   └── system-update.sh    # update command
│   └── apply-optimizations.sh  # NEW: Conditional optimizations
├── docs/
│   ├── HARDWARE-AGNOSTIC-ARCHITECTURE.md  # This file
│   ├── SETTINGS-DOCUMENTATION.md          # NEW: Every setting documented
│   └── SYSTEM-STATE.md                    # Current frozen config
└── configs/
    └── templates/              # NEW: Config templates with variables
        ├── kwinoutputconfig.template
        └── grub-nvidia.template
```
