#!/usr/bin/env bash
# =============================================================================
# update-now.sh - apply the prepared update from any terminal, without a TTY
# =============================================================================
# Runs `update-engine.sh install` as a transient systemd unit, so it is not a
# child of the graphical session: a hanging kwin cannot take the transaction
# down with it. The GUI is stopped just before the unit starts, because
# replacing Qt/Plasma/Mesa underneath a running compositor is what froze this
# machine on 2026-10-23.
#
#   1. queues garuda-update-now.service (offline, from the package cache)
#   2. waits DELAY seconds (default 20) so you can save your work
#   3. stops the graphical session
#  10. the update runs on a text console, independent of any session
#
# Usage:  sudo ./scripts/tools/update-now.sh
#         DELAY=60 sudo ./scripts/tools/update-now.sh
#
# Abort:  Ctrl+C during the countdown (cancels the queued unit).
# Result: /var/log/garuda/system-update-*.log, journalctl -u garuda-update-now
# Reboot after it finishes.
# =============================================================================
set -Eeuo pipefail

UNIT="garuda-update-now"
DELAY="${DELAY:-20}"
LEAD=$((DELAY + 10))
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_DIR="$(dirname "$SELF")"
ENGINE="$SELF_DIR/update-engine.sh"
LOCAL_ENGINE="/usr/local/lib/garuda-restore/update-engine.sh"

if [ "$EUID" -ne 0 ]; then
    exec sudo --preserve-env=DELAY -- "$SELF" "$@"
fi

if [ ! -x "$ENGINE" ]; then
    echo "FATAL: missing $ENGINE" >&2
    exit 1
fi
if [ -e /var/lib/pacman/db.lck ]; then
    echo "FATAL: pacman is locked (/var/lib/pacman/db.lck)" >&2
    exit 1
fi
if ! pacman -Dk >/dev/null 2>&1; then
    echo "FATAL: local pacman DB is inconsistent - run update-engine.sh prepare first" >&2
    exit 1
fi

# The transient unit must not depend on this repo or the external drive.
install -Dm755 "$ENGINE" "$LOCAL_ENGINE"

systemctl stop "$UNIT.timer" "$UNIT.service" 2>/dev/null || true
systemctl reset-failed "$UNIT.timer" "$UNIT.service" 2>/dev/null || true

abort() {
    systemctl stop "$UNIT.timer" "$UNIT.service" 2>/dev/null || true
    echo
    echo "Aborted: the queued update was cancelled, nothing was installed."
    exit 130
}
trap abort INT TERM

systemd-run --on-active="$LEAD" --unit="$UNIT" --collect \
    --property=StandardOutput=journal+console \
    --property=StandardError=journal+console \
    --property=TimeoutStartSec=infinity \
    "$LOCAL_ENGINE" install --force --offline

cat <<INFO
Queued: $UNIT.service (offline, from /var/cache/pacman/pkg; starts in ${LEAD}s).

The graphical session stops in ${DELAY}s and this terminal closes with it.
Save your work now. Ctrl+C cancels the update.

Watch it from a text console:  journalctl -u $UNIT -f
Result log:                    /var/log/garuda/system-update-*.log
After it finishes:             sudo reboot
If it fails:                   log in on the console, sudo systemctl start graphical.target
INFO

for ((i = DELAY; i > 0; i--)); do
    printf '\r  stopping the graphical session in %2ds ' "$i"
    sleep 1
done
printf '\r  stopping the graphical session...            \n'

systemctl isolate multi-user.target
