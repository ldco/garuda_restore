#!/bin/bash
# ============================================================================
# System Fixes Application Script
# ============================================================================
# Applies fixes identified in SYSTEM-ANALYSIS.md
# Each fix has confirmation, backup, and rollback capability
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config/system-fixes-backup-$(date +%Y%m%d-%H%M%S)"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           System Fixes Application Script                            ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "This script will apply safe system fixes with your confirmation."
echo "Backups will be saved to: $BACKUP_DIR"
echo ""

mkdir -p "$BACKUP_DIR"

# ============================================================================
# FIX 1: Samba - Bind to Local Network Only
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 1: Samba Security - Bind to Local Network Only"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Current status:"
ss -tlnp 2>/dev/null | grep -E "139|445" | head -5 || echo "Cannot check (need root)"
echo ""
echo "Issue: Samba ports 139/445 are exposed on 0.0.0.0 (all interfaces)"
echo "Fix: Bind only to 127.0.0.1 and 192.168.1.0/24"
echo ""
read -p "Apply this fix? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Backing up /etc/samba/smb.conf..."
    sudo cp /etc/samba/smb.conf "$BACKUP_DIR/smb.conf.backup"

    # Check if interfaces line already exists
    if grep -q "^interfaces" /etc/samba/smb.conf; then
        echo "interfaces already configured, skipping..."
    else
        echo "Adding interface binding..."
        sudo sed -i '/^\[global\]/a\   interfaces = 127.0.0.1 192.168.1.0/24\n   bind interfaces only = yes' /etc/samba/smb.conf

        echo "Restarting Samba..."
        sudo systemctl restart smb nmb

        echo "✓ Samba fix applied"
        echo "Verify: ss -tlnp | grep -E '139|445'"
    fi
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# FIX 2: Blacklist spd5118 Driver
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 2: Blacklist spd5118 DDR5 Temperature Sensor Driver"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Issue: spd5118 driver causes resume errors after suspend"
echo "       'spd5118_resume returns -6' spam in logs"
echo "Fix: Blacklist the module (DDR5 temp monitoring will be disabled)"
echo ""
echo "Current status:"
lsmod | grep spd5118 && echo "Module is loaded" || echo "Module not loaded or already blacklisted"
echo ""
read -p "Apply this fix? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -f /etc/modprobe.d/blacklist-spd5118.conf ]; then
        echo "Already blacklisted, skipping..."
    else
        echo "Creating blacklist file..."
        echo "blacklist spd5118" | sudo tee /etc/modprobe.d/blacklist-spd5118.conf

        echo ""
        echo "✓ Blacklist created"
        echo "Note: Reboot required for full effect"
        echo "To verify after reboot: lsmod | grep spd5118 (should be empty)"
    fi
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# FIX 3: KWin Hybrid GPU Fix (nvidia_drm.fbdev=1)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 3: KWin Hybrid GPU Fix (nvidia_drm.fbdev=1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Issue: KWin framebuffer errors with Intel/NVIDIA hybrid GPU on Wayland"
echo "       'GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT' spam in logs"
echo "Fix: Add nvidia_drm.fbdev=1 kernel parameter (power-safe, won't overheat)"
echo ""
echo "Current kernel params:"
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub
echo ""
echo "Current framebuffer error count this boot:"
journalctl -b 2>/dev/null | grep -c "framebuffer" || echo "Cannot check"
echo ""
read -p "Apply this fix? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Check if already applied
    if grep -q "nvidia_drm.fbdev=1" /etc/default/grub; then
        echo "nvidia_drm.fbdev=1 already in GRUB config, skipping..."
    else
        echo "Backing up GRUB config..."
        sudo cp /etc/default/grub "$BACKUP_DIR/grub.backup"

        echo "Adding nvidia_drm.modeset=1 nvidia_drm.fbdev=1 to kernel params..."
        # Replace the GRUB_CMDLINE_LINUX_DEFAULT line to add nvidia params
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3'/GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3 nvidia_drm.modeset=1 nvidia_drm.fbdev=1'/" /etc/default/grub

        echo "Regenerating GRUB config..."
        sudo grub-mkconfig -o /boot/grub/grub.cfg

        echo ""
        echo "✓ KWin fix applied"
        echo "Note: Reboot required for this to take effect"
        echo "After reboot, check: journalctl -b | grep -c 'framebuffer'"
    fi
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# FIX 4: GRUB Timeout Optimization (Optional)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 4: GRUB Timeout Optimization (Optional)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Current timeout:"
grep "GRUB_TIMEOUT=" /etc/default/grub
echo ""
echo "Change: Reduce from 5 seconds to 2 seconds for faster boot"
echo ""
read -p "Apply this fix? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Only backup if not already backed up by FIX 3
    if [ ! -f "$BACKUP_DIR/grub.backup" ]; then
        echo "Backing up GRUB config..."
        sudo cp /etc/default/grub "$BACKUP_DIR/grub.backup"
    fi

    echo "Updating timeout..."
    sudo sed -i 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' /etc/default/grub

    echo "Regenerating GRUB config..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    echo "✓ GRUB timeout updated to 2 seconds"
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# FIX 5: Run Btrfs Scrub (Data Verification)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 5: Run Btrfs Scrub (Data Verification)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This verifies data integrity on your btrfs filesystem."
echo "It runs in background and may take 10-30 minutes."
echo "System remains fully usable during scrub."
echo ""
read -p "Start btrfs scrub? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting btrfs scrub..."
    sudo btrfs scrub start /
    echo ""
    echo "✓ Scrub started in background"
    echo "Check status: sudo btrfs scrub status /"
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# FIX 6: Disable Mullvad VPN Daemon (Not Using)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 6: Disable Mullvad VPN Daemon"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Issue: Mullvad VPN daemon running but not being used"
echo "Fix: Disable the service (can re-enable anytime)"
echo ""
echo "Current status:"
systemctl is-active mullvad-daemon 2>/dev/null || echo "Not running"
echo ""
read -p "Disable mullvad-daemon? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if systemctl is-active mullvad-daemon &>/dev/null; then
        echo "Disabling mullvad-daemon..."
        sudo systemctl disable --now mullvad-daemon
        echo "✓ Mullvad daemon disabled"
        echo "To re-enable: sudo systemctl enable --now mullvad-daemon"
    else
        echo "Already disabled or not installed, skipping..."
    fi
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# FIX 7: Pacman Parallel Downloads
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "FIX 7: Pacman Parallel Downloads"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Current setting:"
grep "ParallelDownloads" /etc/pacman.conf
echo ""
echo "Change: Increase from 5 to 10 parallel downloads"
echo ""
read -p "Apply this fix? [y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    current=$(grep "ParallelDownloads" /etc/pacman.conf | grep -o '[0-9]*')
    if [ "$current" -ge 10 ] 2>/dev/null; then
        echo "Already set to $current, skipping..."
    else
        echo "Backing up pacman.conf..."
        sudo cp /etc/pacman.conf "$BACKUP_DIR/pacman.conf.backup"

        echo "Updating ParallelDownloads..."
        sudo sed -i 's/ParallelDownloads = 5/ParallelDownloads = 10/' /etc/pacman.conf

        echo "✓ Pacman parallel downloads set to 10"
    fi
else
    echo "Skipped."
fi
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                         FIXES COMPLETE                               ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Backups saved to: $BACKUP_DIR"
echo ""
echo "Recommended next steps:"
echo "  1. Review any applied fixes above"
echo "  2. Reboot to apply kernel module blacklist and GRUB changes"
echo "  3. After reboot, verify fixes with:"
echo "     - journalctl -b | grep -c 'framebuffer'  (should be lower)"
echo "     - lsmod | grep spd5118  (should be empty)"
echo "     - cat /proc/cmdline | grep nvidia  (should show nvidia_drm params)"
echo "     - sudo btrfs scrub status /"
echo ""
echo "To rollback any fix:"
echo "  - Samba: sudo cp $BACKUP_DIR/smb.conf.backup /etc/samba/smb.conf && sudo systemctl restart smb nmb"
echo "  - spd5118: sudo rm /etc/modprobe.d/blacklist-spd5118.conf && reboot"
echo "  - GRUB/KWin: sudo cp $BACKUP_DIR/grub.backup /etc/default/grub && sudo grub-mkconfig -o /boot/grub/grub.cfg && reboot"
echo "  - Mullvad: sudo systemctl enable --now mullvad-daemon"
echo "  - Pacman: sudo cp $BACKUP_DIR/pacman.conf.backup /etc/pacman.conf"
echo ""
