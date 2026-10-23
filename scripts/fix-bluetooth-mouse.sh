#!/bin/bash
# ============================================================================
# FIX BLUETOOTH MOUSE - stop BT HID devices dropping and needing a re-pair
# ============================================================================
# Requires root. Idempotent. Backs up every file before touching it.
#
#   sudo ./scripts/fix-bluetooth-mouse.sh              # apply
#   sudo ./scripts/fix-bluetooth-mouse.sh --kernel-ab  # show the kernel A/B plan
#   sudo ./scripts/fix-bluetooth-mouse.sh --kernel-ab --yes   # execute it
#   sudo ./scripts/fix-bluetooth-mouse.sh --revert     # undo the BlueZ change
#
# What it changes and why:
#
#  1. BlueZ [Policy] ReconnectAttempts / ReconnectIntervals
#     Unset by default => "setting the value to 0 disables reconnecting
#     feature". After a link loss bluetoothd does nothing, so a dropped device
#     stays dead until you re-pair it. This makes it retry instead.
#
#  2. btusb enable_autosuspend=0 (/etc/modprobe.d)
#     Stops the BT controller entering USB selective suspend. Takes effect on
#     reboot. Arch already ships reset=1 for the same class of problem.
#
#  3. Restart bluetooth and verify the adapter comes back.
#
# NOT changed: the kernel. See --kernel-ab.
# ============================================================================
set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "error: run as root (sudo $0)" >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
CONF=/etc/bluetooth/main.conf
MODPROBE=/etc/modprobe.d/zz-btusb-hardening.conf

# ---------------------------------------------------------------------------
# --revert
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--revert" ]; then
    last="$(ls -1t "$CONF".orig-* 2>/dev/null | head -1 || true)"
    if [ -z "$last" ]; then
        echo "no backup found matching $CONF.orig-*"
        exit 1
    fi
    cp -a "$last" "$CONF"
    echo "✓ restored $CONF from $last"
    systemctl restart bluetooth
    echo "✓ bluetooth restarted"
    exit 0
fi

echo "=== 1. BlueZ reconnect policy ==="
if [ -f "$CONF" ]; then
    if grep -qE '^ReconnectAttempts=' "$CONF"; then
        echo "  = already enabled"
    else
        cp -a "$CONF" "$CONF.orig-$STAMP"
        sed -i 's/^#[[:space:]]*ReconnectAttempts=.*/ReconnectAttempts=7/' "$CONF"
        sed -i 's/^#[[:space:]]*ReconnectIntervals=.*/ReconnectIntervals=1,2,4,8,16,32,64/' "$CONF"
        echo "  ✓ enabled (backup: $CONF.orig-$STAMP)"
    fi
    grep -nE '^Reconnect(Attempts|Intervals)=' "$CONF" | sed 's/^/    /'
else
    echo "  ! $CONF missing - is bluez installed?" >&2
fi

echo
echo "=== 2. btusb autosuspend ==="
if [ -f "$MODPROBE" ]; then
    echo "  = already configured ($MODPROBE)"
else
    cat > "$MODPROBE" <<'EOF'
# Disable USB autosuspend for the Bluetooth controller (btusb).
# Arch ships `options btusb reset=1` in bluetooth-usb.conf for the same class
# of problem. Autosuspend lets the controller enter USB selective suspend while
# a BLE HID device is idle, which can drop the link.
options btusb enable_autosuspend=0
EOF
    echo "  ✓ written ($MODPROBE) - effective after reboot"
fi

echo
echo "=== 3. restarted bluetooth ==="
systemctl restart bluetooth
sleep 3
if systemctl is-active --quiet bluetooth; then
    echo "  ✓ bluetooth active"
else
    echo "  ✗ bluetooth FAILED to start - check: journalctl -u bluetooth -n 50" >&2
fi
bluetoothctl show 2>/dev/null | grep -E '^\s*(Name|Powered|Discoverable|Pairable):' | sed 's/^/    /' || true

# ---------------------------------------------------------------------------
# Optional: kernel A/B. The BT stack regression candidate from the last
# system update. Only runs when explicitly asked, because it needs a reboot.
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--kernel-ab" ]; then
    echo
    echo "=== 4. kernel A/B (linux-zen downgrade) ==="
    CUR="$(pacman -Q linux-zen 2>/dev/null | awk '{print $2}' || echo unknown)"
    TARGET="$(ls -1t /var/cache/pacman/pkg/linux-zen-7.1.*-x86_64.pkg.tar.zst 2>/dev/null | head -1 || true)"
    echo "  current : linux-zen $CUR"
    echo "  cached  : ${TARGET:-<none available>}"
    if [ -z "$TARGET" ]; then
        echo "  ! no older linux-zen in the pacman cache - cannot A/B offline"
    elif [ "${2:-}" != "--yes" ]; then
        echo
        echo "  dry run. to execute:"
        echo "    sudo $0 --kernel-ab --yes"
        echo
        echo "  This is a TEMPORARY test, not a permanent fix: the next"
        echo "  'pacman -Syu' will pull linux-zen back to $CUR."
        echo "  Read scripts/bt-monitor.sh output before and after to compare."
    else
        echo "  installing $TARGET ..."
        pacman -U --noconfirm "$TARGET"
        echo
        echo "  ⚠  reboot required to test. After reboot:"
        echo "       journalctl --user -u bt-monitor -f"
        echo "     If drops stop  -> the new kernel/firmware is the regression."
        echo "     If drops stay  -> revert with: pacman -Syu  (back to latest)"
        echo "     Durable alternative that avoids BLE entirely: use the Unifying"
        echo "     receiver (hidraw8 / event15) instead of the Bluetooth channel."
    fi
fi

echo
echo "=== verify ==="
echo "  adapter:  btmgmt info | head -3"
echo "  device:   bluetoothctl info <MAC>"
echo "  drops:    bash scripts/bt-monitor.sh <MAC>      (repeat the reason here)"
echo "  undo:     sudo $0 --revert"
