#!/usr/bin/env bash
# =============================================================================
# update-now.sh - apply the prepared update from any terminal, without a TTY
# =============================================================================
# Runs `update-engine.sh install` as a transient systemd unit, so it is not a
# child of the graphical session: a hanging kwin cannot take the transaction
# down with it. The GUI is stopped right after the unit is queued, because
# replacing Qt/Plasma/Mesa underneath a running compositor is what froze this
# machine on 2026-10-23.
#
#   1. switches to tty1 and queues garuda-update-now.service (offline)
#   2. stops the graphical session immediately
#   3. the update runs on a text console, independent of any session
#
# Usage:  sudo ./scripts/tools/update-now.sh
#
# There is no countdown: save your work before running it.
# Result: /var/log/garuda/system-update-*.log, journalctl -u garuda-update-now
# It reboots automatically on success.
# =============================================================================
set -Eeuo pipefail

UNIT="garuda-update-now"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_DIR="$(dirname "$SELF")"
ENGINE="$SELF_DIR/update-engine.sh"
LOCAL_ENGINE="/usr/local/lib/garuda-restore/update-engine.sh"

if [ "$EUID" -ne 0 ]; then
    exec sudo -- "$SELF" "$@"
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

cat > /usr/local/lib/garuda-restore/update-now-run.sh <<'RUNNER'
#!/bin/bash
# Runs as a transient system unit. Must survive `systemctl isolate`, so it is
# started with IgnoreOnIsolate=yes by update-now.sh.
set -u
LOG=/var/log/garuda/update-now-run.log
mkdir -p /var/log/garuda
exec > >(tee -a "$LOG") 2>&1

pending="$(pacman -Qu 2>/dev/null | wc -l || true)"
echo "=============================================================="
echo " Garuda update: graphical session is stopped."
echo " Installing ${pending} packages offline from /var/cache/pacman/pkg."
echo " Do not power off. This unit survives the session shutdown."
echo "=============================================================="
sleep 10

/usr/local/lib/garuda-restore/update-engine.sh install --force --offline
rc=$?

if [ "$rc" -eq 0 ]; then
    mkdir -p /var/lib/garuda-restore
    date -Is > /var/lib/garuda-restore/post-update.pending
    echo "=== SUCCESS - post-update maintenance scheduled for the next boot ==="
    echo "=== rebooting into the new kernel in 10 seconds ==="
    sleep 10
    systemctl reboot
else
    echo "=== FAILED (exit $rc) - returning to the desktop ==="
    echo "=== log: /var/log/garuda/system-update-*.log ==="
    sleep 8
    systemctl start graphical.target
fi
exit 0
RUNNER
chmod 755 /usr/local/lib/garuda-restore/update-now-run.sh

pending="$(pacman -Qu 2>/dev/null | wc -l)"

systemctl stop "$UNIT.timer" "$UNIT.service" 2>/dev/null || true
systemctl reset-failed "$UNIT.timer" "$UNIT.service" 2>/dev/null || true

cat <<INFO
Ready to install ${pending} cached packages.

The graphical session stops NOW and this terminal closes.
Save your work before running this command.

On tty1 you will see live install output, then:
  - automatic reboot on success;
  - the desktop comes back automatically on failure.

Runner log: /var/log/garuda/update-now-run.log
INFO

printf '  stopping the graphical session...\n'

# A transient unit is not part of multi-user.target; without this it would be
# killed by the isolate (that is what happened on 2026-10-23 17:38).
chvt 1 2>/dev/null || true

systemd-run --unit="$UNIT" --collect \
    --property=IgnoreOnIsolate=yes \
    --property=StandardOutput=journal+console \
    --property=StandardError=journal+console \
    --property=TimeoutStartSec=infinity \
    /usr/local/lib/garuda-restore/update-now-run.sh

systemctl isolate multi-user.target
