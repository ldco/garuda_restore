#!/bin/bash
# ============================================================================
# BT MONITOR - record every connect/disconnect and the BlueZ disconnect REASON
# ============================================================================
# Why this exists:
#   When a Bluetooth HID device (mouse/keyboard) drops, the KERNEL JOURNAL IS
#   SILENT. btusb logs connects only. The reason lives in BlueZ as a D-Bus
#   signal, so it is invisible to journalctl and to dmesg.
#   btmon shows it, but btmon requires root.
#
#   `bluetoothctl --monitor` prints the same signals and does NOT need root.
#
# Reason vocabulary (org.bluez.Reason.*):
#   .Timeout        link supervision timeout - host answered too late, or RF
#                   loss. On a loaded machine this means CPU starvation.
#   .Local          local host terminated the link
#   .Remote         the DEVICE ended it (mouse's own power saving, Easy-Switch)
#   .Suspend        system suspend
#   .Authentication bond/keys invalid -> requires re-pairing
#
# Usage:  bt-monitor.sh [ADDRESS] [LOGFILE]
#         bt-monitor.sh                       # all devices, default log
#         bt-monitor.sh C3:3D:5C:EF:A9:05     # tag one device
# ============================================================================
set -u

ADDR="${1:-ALL}"
LOG="${2:-$HOME/.local/share/garuda-backup-scripts/bt-monitor.log}"
mkdir -p "$(dirname "$LOG")"

log() { printf '%s | %s\n' "$(date '+%F %T')" "$1"; }

{
    log "=== monitor start (device=${ADDR}) ==="
    bluetoothctl devices Connected 2>/dev/null | sed 's/^/  already-connected: /'
} >> "$LOG"

# --monitor prints [SIGNAL]/[CHG] lines with ANSI colour codes; strip them and
# keep only link-state and reason lines so the log stays readable for months.
#
# bluetoothctl exits as soon as stdin reaches EOF, which under systemd is
# immediately (restart loop, no output). So stdin is held open forever.
tail -f /dev/null | stdbuf -oL -eL bluetoothctl --monitor 2>&1 \
    | stdbuf -oL sed -u 's/\x1b\[[0-9;]*m//g' \
    | stdbuf -oL grep --line-buffered -E \
        'LE\.Connected|LE\.Disconnected|Connected: (yes|no)|org\.bluez\.Reason\.' \
    | while IFS= read -r line; do
        log "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')"
      done \
    | tee -a "$LOG"
