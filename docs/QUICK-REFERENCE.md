# Quick Reference Card - Garuda KDE System

## Daily Commands

```bash
# Power Profiles
asusctl profile -p                    # Check current
asusctl profile -P Balanced           # Daily work
asusctl profile -P Performance        # Gaming/compiling
asusctl profile -P Quiet              # Silent/battery

# System Status
nvidia-smi                            # GPU state
ps aux | grep kwin                    # KWin CPU usage
sensors                               # Temperatures
```

## If Something Goes Wrong

### Mouse Lag / System Slow
```bash
asusctl profile -P Balanced
```

### KWin High CPU
```bash
# Check if blur was re-enabled
grep "blurEnabled" ~/.config/kwinrc
# Should show: blurEnabled=false
```

### Screen Flickering
```bash
# Verify DDC/CI is disabled
grep "allowDdcCi" ~/.config/kwinoutputconfig.json
# Should show: "allowDdcCi": false
```

### Internal Display Gone
```bash
# Check for KWIN_DRM_DEVICES
cat /etc/environment
# Should NOT contain KWIN_DRM_DEVICES line
```

## Restore Frozen Config

```bash
# From project backup
cd /path/to/garuda-restore/configs/frozen-2024-12-30/
cp etc-environment /etc/environment
cp kwinrc ~/.config/
cp kwinoutputconfig.json ~/.config/
cp kwinrulesrc ~/.config/
cp firefox.conf ~/.config/environment.d/
# Then logout/login
```

## Optimal Baselines

| Metric | Expected Value |
|--------|----------------|
| KWin CPU | 15-25% (3 monitors @ 165Hz) |
| GPU State | P5 (idle), P0-P2 (gaming) |
| GPU Power | 20-30W (idle), 100W+ (gaming) |
| CPU Temp | 40-60C (idle), 80-95C (load) |

## DO NOT

- Enable blur/forceblur/shapecorners in KWin
- Set `allowDdcCi=true` for monitors
- Add `KWIN_DRM_DEVICES` to /etc/environment
- Change `vm.swappiness` from 133
- Manually override CPU governor
- Install schedutil or irqbalance
