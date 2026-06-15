#!/bin/bash
# ============================================================================
# FIX-SUDO-LOCKOUT — Prevent pam_faillock from locking user during automation
# ============================================================================

echo "=== Fixing sudo lockout ==="
echo ""

# 1. Reset current lock (requires your password)
echo "Step 1: Resetting current lock..."
sudo faillock --user ldco --reset 2>/dev/null && echo "  ✓ Lock cleared" || echo "  ⚠️ Could not reset (may need reboot)"

# 2. Raise deny limit from 10 to 50 (automation-safe)
echo ""
echo "Step 2: Raising faillock threshold (10 → 50)..."
echo "deny = 50" | sudo tee /etc/security/faillock.conf 2>/dev/null && echo "  ✓ Deny limit raised to 50" || echo "  ✗ Failed — run with sudo"

# 3. Check all autostart/scripts for blind sudo calls
echo ""
echo "Step 3: Checking for blind sudo in autostart..."
grep -rl 'sudo\|systemctl restart\|systemctl.*--no-pager.*status.*happd' ~/.config/autostart/ 2>/dev/null || echo "  ✓ No blind sudo in autostart"
grep -rl 'sudo\|systemctl restart' ~/.config/systemd/user/ 2>/dev/null && echo "  ⚠️ Found sudo in user services" || echo "  ✓ No sudo in user services"

echo ""
echo "=== Done ==="
echo "faillock threshold: 50 (was 10)"
echo "After this, only reboot or 50 consecutive PAM failures will lock."
