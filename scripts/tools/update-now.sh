#!/usr/bin/env bash
# =============================================================================
# update-now.sh - install the staged update with no graphical session
# =============================================================================
# Runs the install from a real systemd unit (garuda-update-now.service), not
# from a transient `systemd-run` unit and not from this terminal:
#
#   * the unit declares Conflicts=graphical.target + After=graphical.target, so
#     starting it stops the desktop as a dependency effect and the install
#     begins only after Plasma is gone (replacing Qt/Mesa under a live
#     compositor is what froze this machine on 2026-10-23);
#   * pid 1 owns the process, so the graphical teardown cannot stop it. The
#     transient-unit design did exactly that twice: 2026-10-23 17:38 and
#     2026-11-11 00:51 (the unit was "Deactivated successfully" 5 s in and
#     installed nothing);
#   * the staged cache is verified BEFORE anything is touched - network-free,
#     ~1 s. On 2026-11-10 a `pacman -Sc` had purged the staged 8.7 GiB and the
#     "offline" install downloaded it all over again on tty1 instead of
#     refusing.
#
# Usage:  sudo ./scripts/tools/update-now.sh
#         sudo ./scripts/tools/update-now.sh --dry-run   # checks only, changes nothing
#
# There is no countdown: the desktop stops as soon as the checks pass.
# Watch it after the desktop is gone: Ctrl+Alt+F1/F3, log in, then
#   journalctl -u garuda-update-now -f
# Transcript: /var/log/garuda/update-now-run.log
# It reboots automatically on success; on failure the desktop comes back.
# =============================================================================
set -Eeuo pipefail

UNIT="garuda-update-now"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SELF_DIR="$(dirname "$SELF")"
REPO_DIR="$(dirname "$(dirname "$SELF_DIR")")"
ENGINE="$SELF_DIR/update-engine.sh"
# The timer stack installs a copy of this script in /usr/local/lib/garuda-restore
# and calls it directly, so look for the unit next to the script first.
UNIT_SRC="$SELF_DIR/garuda-update-now.service"
[ -r "$UNIT_SRC" ] || UNIT_SRC="$REPO_DIR/systemd/garuda-update-now.service"
LOCAL_DIR="/usr/local/lib/garuda-restore"
LOCAL_ENGINE="$LOCAL_DIR/update-engine.sh"
RUNNER="$LOCAL_DIR/update-now-run.sh"
RESTORE="$LOCAL_DIR/update-now-restore.sh"
UNIT_FILE="/etc/systemd/system/$UNIT.service"
FLAG="/var/lib/garuda-restore/update-now.request"
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,32p' "$SELF" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            printf 'unknown argument: %s (try --help)\n' "$1" >&2
            exit 2
            ;;
    esac
    shift
done

[ -x "$ENGINE" ] || { printf 'FATAL: missing %s\n' "$ENGINE" >&2; exit 1; }
if [ ! -r "$UNIT_SRC" ]; then
    printf 'FATAL: missing %s\n' "$UNIT_SRC" >&2
    printf '       the timer stack installs this script without the unit -\n' >&2
    printf '       refresh the installed copies: sudo ./scripts/tools/install-update-timer.sh\n' >&2
    exit 1
fi

staged_count() { pacman -Sup --print-format '%n' 2>/dev/null | grep -c . || true; }
# Size of the staged set as it sits in the cache (pacman's %s is the *download*
# size, which is 0 once everything is cached).
staged_mib() {
    local n v a
    pacman -Sup --print-format '%n %v %a' 2>/dev/null \
        | while read -r n v a; do
            stat -c %s "/var/cache/pacman/pkg/$n-$v-$a.pkg.tar.zst" 2>/dev/null \
                || stat -c %s "/var/cache/pacman/pkg/$n-$v-$a.pkg.tar.xz" 2>/dev/null \
                || echo 0
        done \
        | awk '{ s += $1 } END { printf "%.1f", s / 1048576 }'
}

# ---------------------------------------------------------------------------
# Gate: never stop the desktop for a transaction that cannot start.
# `install --check-cache` is read-only, root-free and network-free.
# Returns 0 = ready, 1 = not installable, 2 = nothing staged.
# ---------------------------------------------------------------------------
cache_gate() {
    local engine="$1" count size
    count="$(staged_count)"
    size="$(staged_mib)"
    printf 'Staged for install: %s packages, %s MiB in /var/cache/pacman/pkg\n' "$count" "$size"

    if [ "$count" -eq 0 ]; then
        printf 'Nothing to install: no repo upgrades are staged. The desktop was NOT stopped.\n'
        return 2
    fi

    if ! "$engine" install --offline --check-cache; then
        cat <<'GATE' >&2
FATAL: the staged package cache is incomplete or stale.
       Nothing was installed and the desktop was NOT stopped.

Fix it from the desktop (network needed, progress is visible there):
       sudo ./scripts/tools/update-engine.sh prepare

Then run this command again. Do not run 'sudo pacman -Sc' or 'paccache' in
between: they delete the staged packages from the cache and the whole
download has to repeat.
GATE
        return 1
    fi
    return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
    rc=0
    cache_gate "$ENGINE" || rc=$?
    case "$rc" in
        0)
            printf '\nUnit that would be started:\n'
            grep -vE '^\s*(#|$)' "$UNIT_SRC" | sed 's/^/    /'
            printf '\n[dry-run] checks passed. Nothing was changed and the desktop was NOT stopped.\n'
            exit 0
            ;;
        2) exit 0 ;;
        *) exit 1 ;;
    esac
fi

if [ "$EUID" -ne 0 ]; then
    exec sudo -- "$SELF" "$@"
fi

if [ -e /var/lib/pacman/db.lck ]; then
    printf 'FATAL: pacman is locked (/var/lib/pacman/db.lck)\n' >&2
    exit 1
fi
if ! pacman -Dk >/dev/null 2>&1; then
    printf 'FATAL: local pacman DB is inconsistent - run update-engine.sh prepare first\n' >&2
    exit 1
fi

# 1. Gate first: the desktop is not touched when the cache is not installable.
gate_rc=0
cache_gate "$ENGINE" || gate_rc=$?
case "$gate_rc" in
    0) : ;;
    2) exit 0 ;;
    *) exit 1 ;;
esac

# 2. The unit must not depend on this repo or the external drive.
install -Dm755 "$ENGINE" "$LOCAL_ENGINE"
cat > "$RUNNER" <<'RUNNER_EOF'
#!/bin/bash
# Installs the staged update with no graphical session and no interaction.
# Started by garuda-update-now.service (Conflicts=graphical.target): the desktop
# is already gone when this begins and pid 1 owns this process.
#
# Nobody has to log in on a console: tty1 is taken over (getty is stopped, so
# there is no login prompt), every line is mirrored to that screen, to the
# journal and to the transcript. A failure brings the desktop back through
# update-now-restore.sh and posts a notification.
set -u

LOG=/var/log/garuda/update-now-run.log
ENGINE=/usr/local/lib/garuda-restore/update-engine.sh
RESTORE=/usr/local/lib/garuda-restore/update-now-restore.sh
FLAG=/var/lib/garuda-restore/update-now.request

mkdir -p /var/log/garuda
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 5000000 ]; then
    mv -f "$LOG" "$LOG.1"
fi

# --- own the console: no login prompt, progress on screen -------------------
USE_CONSOLE=0
if [ -w /dev/tty1 ]; then
    systemctl stop getty@tty1.service >/dev/null 2>&1 || true
    chvt 1 >/dev/null 2>&1 || true
    sleep 1
    setterm --blank 0 --powerdown 0 </dev/tty1 >/dev/tty1 2>/dev/null || true
    printf '\033[2J\033[H' >/dev/tty1 2>/dev/null || true
    if [ -w /dev/tty1 ]; then
        USE_CONSOLE=1
    fi
fi

if [ "$USE_CONSOLE" -eq 1 ]; then
    exec 3>&1
    exec > >(tee -a "$LOG" /dev/tty1 >&3) 2>&1
else
    exec > >(tee -a "$LOG") 2>&1
fi

rm -f "$FLAG"

echo "=============================================================="
echo " Garuda system update: $(date -Is)"
echo " Installing the staged packages from /var/cache/pacman/pkg."
echo " No download is attempted: the cache was verified before start."
echo " Leave the machine alone - it reboots by itself when done."
if [ "$USE_CONSOLE" -eq 1 ]; then
    echo " Progress is printed below. Nothing to type here."
fi
echo " Journal:    journalctl -u garuda-update-now"
echo " Transcript: $LOG"
echo "=============================================================="

# The desktop is stopped before this unit starts; give a lingering compositor
# or a closing logind session a moment so the engine's own GUI guard does not
# fire on something that is already dying.
session_alive() {
    local sid type active
    while read -r sid _; do
        [ -n "$sid" ] || continue
        type="$(loginctl show-session "$sid" -p Type --value 2>/dev/null || true)"
        active="$(loginctl show-session "$sid" -p Active --value 2>/dev/null || true)"
        case "$type" in
            wayland|x11) [ "$active" = "yes" ] && return 0 ;;
        esac
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
    return 1
}

graphical_alive() {
    pgrep -x kwin_wayland >/dev/null 2>&1 \
        || pgrep -x kwin_x11 >/dev/null 2>&1 \
        || pgrep -x Xorg >/dev/null 2>&1 \
        || session_alive
}
for _ in $(seq 1 30); do
    graphical_alive || break
    sleep 2
done

# No --force: if a compositor is still alive the engine refuses, and returning
# to the desktop is safer than replacing Qt underneath a dying Plasma.
"$ENGINE" install --offline
rc=$?

if [ "$rc" -eq 0 ]; then
    mkdir -p /var/lib/garuda-restore
    date -Is > /var/lib/garuda-restore/post-update.pending
    echo "=== SUCCESS - post-update maintenance scheduled for the next boot ==="
    echo "=== rebooting into the new kernel in 10 seconds ==="
    sync
    sleep 10
    systemctl reboot
else
    echo "=== FAILED (exit $rc) - bringing the desktop back ==="
    echo "=== transcript: $LOG ==="
    sleep 2
    # A separate unit restores the desktop and notifies the user: starting
    # graphical.target conflicts with THIS unit, so the work cannot stay here.
    systemd-run --collect --no-block --unit=garuda-update-restore "$RESTORE" \
        || echo "WARN: could not queue the desktop restore - run: sudo systemctl start graphical.target"
fi
exit 0
RUNNER_EOF
chmod 755 "$RUNNER"

cat > "$RESTORE" <<'RESTORE_EOF'
#!/bin/bash
# Brings the desktop back after a failed install and tells the user what
# happened as a desktop notification - no console login required.
set -u

LOG=/var/log/garuda/update-now-run.log

systemctl start getty@tty1.service >/dev/null 2>&1 || true
systemctl start graphical.target

SESSION_USER=""
SESSION_ENV=()
detect_session() {
    SESSION_USER=""
    SESSION_ENV=()
    local s t a u uid wd
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
        t=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
        a=$(loginctl show-session "$s" -p Active --value 2>/dev/null || true)
        u=$(loginctl show-session "$s" -p Name --value 2>/dev/null || true)
        case "${t:-}" in wayland|x11) ;; *) continue ;; esac
        [ "${a:-}" = "yes" ] || continue
        uid=$(id -u "$u" 2>/dev/null) || continue
        [ -d "/run/user/$uid" ] || continue
        wd=$(ls /run/user/"$uid"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 || true)
        SESSION_ENV=(XDG_RUNTIME_DIR="/run/user/$uid"
                     DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
                     QT_QPA_PLATFORM=wayland)
        if [ -n "${wd:-}" ]; then
            SESSION_ENV+=(WAYLAND_DISPLAY="$(basename "$wd")")
        fi
        SESSION_USER="$u"
        return 0
    done
    return 1
}

for _ in $(seq 1 30); do
    detect_session && break
    sleep 2
done
[ -n "$SESSION_USER" ] || exit 0

runuser -u "$SESSION_USER" -- env "${SESSION_ENV[@]}" \
    notify-send --app-name="System update" --urgency=critical \
    "System update failed" \
    "The install did not finish. Details: $LOG" >/dev/null 2>&1 || true
exit 0
RESTORE_EOF
chmod 755 "$RESTORE"

bash -n "$RUNNER" || { printf 'FATAL: runner has a syntax error\n' >&2; exit 1; }
bash -n "$RESTORE" || { printf 'FATAL: restore script has a syntax error\n' >&2; exit 1; }
[ -x "$RUNNER" ] || { printf 'FATAL: %s is not executable\n' "$RUNNER" >&2; exit 1; }
[ -x "$RESTORE" ] || { printf 'FATAL: %s is not executable\n' "$RESTORE" >&2; exit 1; }

install -Dm644 "$UNIT_SRC" "$UNIT_FILE"
systemctl daemon-reload

# Refuse to stop the desktop on a unit systemd cannot even load.
verify_out="$(systemd-analyze verify "$UNIT_FILE" 2>&1 || true)"
if grep -qE 'Unable to locate executable|Unknown (key|lvalue)|Invalid (setting|argument)' <<<"$verify_out"; then
    printf '%s\n' "$verify_out" >&2
    printf 'FATAL: %s did not verify - desktop left untouched\n' "$UNIT_FILE" >&2
    exit 1
fi

mkdir -p "$(dirname "$FLAG")"
date -Is > "$FLAG"
systemctl reset-failed "$UNIT" 2>/dev/null || true

cat <<INFO
Checks passed. The desktop now stops and the install runs unattended.

You do not need to log in anywhere: the progress is printed on this screen
(no login prompt), and the machine reboots by itself when the install is done.
If it fails, the desktop comes back on its own with a notification.

Transcript: /var/log/garuda/update-now-run.log
INFO

printf '  starting %s.service (this stops the graphical session)...\n' "$UNIT"
systemctl start --no-block "$UNIT"
exit 0
