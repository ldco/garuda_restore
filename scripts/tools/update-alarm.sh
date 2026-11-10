#!/bin/bash
# =============================================================================
# update-alarm.sh - report a failed update unit instead of waiting to be noticed
# =============================================================================
# Invoked as garuda-update-alarm@<unit>.service, which is the OnFailure= target
# of update-prepare.service, update-prompt.service and garuda-update-now.service.
#
# Why: the whole point of the pipeline is that a developer does not have to
# think about updates. Until this existed, a failed Friday staging was silent -
# evidence in /var/log/garuda and nothing else. Now the failure writes a report
# with the unit status, broadcasts it to every tty and notifies the desktop.
#
# Rate limit: one report per unit per hour, so a repeated failure cannot turn
# into a notification storm.
# =============================================================================
set -u

UNIT="${1:-unknown}"
STATE=/var/lib/garuda-restore
LOG="$STATE/alerts.log"
STAMP="$STATE/alerts.$UNIT.stamp"
mkdir -p "$STATE"

now="$(date +%s)"
last="$(cat "$STAMP" 2>/dev/null || echo 0)"
if [ $((now - last)) -lt 3600 ]; then
    exit 0
fi
printf '%s\n' "$now" > "$STAMP"

{
    printf '=== %s %s failed ===\n' "$(date -Is)" "$UNIT"
    systemctl status "$UNIT" --no-pager -n 30 2>&1 | sed 's/^/  /'
    printf '  log: /var/log/garuda/  |  journalctl -u %s -b\n\n' "$UNIT"
} >> "$LOG"

msg="$UNIT failed - see $LOG"
wall "System update problem: $msg" 2>/dev/null || true

# desktop notification, if somebody is logged in
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
        [ -n "${wd:-}" ] && SESSION_ENV+=(WAYLAND_DISPLAY="$(basename "$wd")")
        SESSION_USER="$u"
        return 0
    done
    return 1
}

if detect_session; then
    runuser -u "$SESSION_USER" -- env "${SESSION_ENV[@]}" \
        notify-send --app-name="System update" --urgency=critical \
        "System update problem" "$msg" >/dev/null 2>&1 || true
fi
exit 0
