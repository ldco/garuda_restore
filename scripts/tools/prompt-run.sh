#!/bin/bash
# =============================================================================
# prompt-run.sh - keep asking until the user installs (or the next Friday)
# =============================================================================
# Called by update-prompt.timer every 5 minutes. It does nothing unless:
#   - MODE=semi in /etc/garuda-restore/update.conf
#   - packages are staged (pending > 0) and no staging/install is running
#   - the reminder interval has elapsed
#
# Cadence after the first decline/timeout at staging time:
#   +1 hour, then every 3 hours, until INSTALL or until the next Friday run
#   (the Friday run resets the cadence).
#
# "Install now" hands over to update-now.sh (GUI stops, install on tty1, reboot).
# =============================================================================
set -u

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# Test hooks: NOCOWBOY_STATE / NOCOWBOY_LOG let the cadence logic be exercised
# without touching the real state directory.
LOG="${NOCOWBOY_LOG:-/var/log/garuda/update-prompt.log}"
STATE="${NOCOWBOY_STATE:-/var/lib/garuda-restore}"
STATUS="$STATE/prepare.status"
PROMPT_STATE="$STATE/prompt.state"
UPDATE_NOW=/usr/local/lib/garuda-restore/update-now.sh
CONF=/etc/garuda-restore/update.conf

MODE=semi
PROMPT_TIMEOUT=600
REMIND_FIRST=3600
REMIND_EVERY=10800
[ -r "$CONF" ] && . "$CONF"

if [ "$DRY_RUN" -eq 0 ]; then
    [ "$(id -u)" -eq 0 ] || { echo "prompt-run: needs root (or --dry-run)" >&2; exit 1; }
    mkdir -p "$STATE" "$(dirname "$LOG")"
    exec >>"$LOG" 2>&1
fi

[ "$MODE" = "semi" ] || { [ "$DRY_RUN" -eq 1 ] && echo "mode=$MODE: no prompts"; exit 0; }

# staged? no lock, no engine running
[ -e /var/lib/pacman/db.lck ] && exit 0
pgrep -f "update-engine.sh (prepare|install)" >/dev/null 2>&1 && exit 0
pending=$(pacman -Qu 2>/dev/null | wc -l)
[ "$pending" -gt 0 ] || { rm -f "$PROMPT_STATE"; exit 0; }
[ -r "$STATUS" ] || exit 0
case "$(sed -n 's/.*phase=\([a-z-]*\).*/\1/p' "$STATUS")" in
    staged) ;;
    *) exit 0 ;;   # preparing / handover / failed: let the Friday run own it
esac

# due?
now=$(date +%s)
LAST_PROMPT=0
DECLINES=0
[ -r "$PROMPT_STATE" ] && . "$PROMPT_STATE"
interval=$REMIND_FIRST
[ "${DECLINES:-0}" -ge 1 ] && interval=$REMIND_EVERY
age=$((now - ${LAST_PROMPT:-0}))
if [ "$age" -lt "$interval" ]; then
    [ "$DRY_RUN" -eq 1 ] && echo "not due: $((interval - age))s left (declines=${DECLINES:-0}, interval=${interval}s)"
    exit 0
fi
[ "$DRY_RUN" -eq 1 ] && echo "due: age=${age}s >= interval=${interval}s, pending=${pending}, declines=${DECLINES:-0}"

# --- active session ---------------------------------------------------------
SESSION_USER=""
SESSION_ENV=()
for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    t=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
    a=$(loginctl show-session "$s" -p Active --value 2>/dev/null || true)
    u=$(loginctl show-session "$s" -p Name --value 2>/dev/null || true)
    case "${t:-}" in wayland|x11) ;; *) continue ;; esac
    [ "${a:-}" = yes ] && [ -n "${u:-}" ] || continue
    uid=$(id -u "$u" 2>/dev/null) || continue
    SESSION_USER="$u"
    SESSION_ENV=(XDG_RUNTIME_DIR="/run/user/$uid"
                 DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
                 QT_QPA_PLATFORM=wayland)
    wd=$(ls /run/user/"$uid"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 || true)
    [ -n "${wd:-}" ] && SESSION_ENV+=(WAYLAND_DISPLAY="$(basename "$wd")")
    break
done
[ -n "$SESSION_USER" ] || { echo "skip: no active graphical session"; exit 0; }
[ "$DRY_RUN" -eq 1 ] && { echo "would prompt user $SESSION_USER"; exit 0; }

as_session() { runuser -u "$SESSION_USER" -- env "${SESSION_ENV[@]+"${SESSION_ENV[@]}"}" "$@"; }

# --- ask --------------------------------------------------------------------
cache=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
body="${pending} packages are staged (cache ${cache}). Install now? The desktop will close and the machine will reboot."
echo "prompt: pending=$pending declines=$DECLINES age=${age}s"

if as_session timeout "$PROMPT_TIMEOUT" kdialog --title "System update" \
        --yes-label "Install now" --no-label "Later" \
        --geometry 760x240 --yesno "$body"; then
    echo "prompt: user chose INSTALL"
    if [ -x "$UPDATE_NOW" ]; then
        "$UPDATE_NOW"
        rc=$?
        rm -f "$PROMPT_STATE"
        echo "=== handover rc=$rc; install result: /var/log/garuda/update-now-run.log ==="
        exit "$rc"
    fi
    echo "FATAL: missing $UPDATE_NOW"
    exit 1
fi

# declined or timed out -> next reminder
NEW_DECLINES=$(( ${DECLINES:-0} + 1 ))
printf 'LAST_PROMPT=%s\nDECLINES=%s\n' "$now" "$NEW_DECLINES" > "$PROMPT_STATE"
if [ "$NEW_DECLINES" -eq 1 ]; then
    echo "prompt: later - next reminder in $((REMIND_FIRST / 60)) min"
else
    echo "prompt: later - next reminder in $((REMIND_EVERY / 3600)) h"
fi
exit 0
