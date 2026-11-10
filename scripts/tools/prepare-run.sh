#!/bin/bash
# =============================================================================
# prepare-run.sh - Friday upgrade run: warn, stage, ask, (maybe) apply
# =============================================================================
# Modes (/etc/garuda-restore/update.conf):
#   MODE=semi   warn 5 min ahead, stage, then a GUI yes/no prompt before applying
#   MODE=auto   warn, stage, apply and reboot without asking
#   MODE=stage  warn, stage only (apply later with update-now.sh)
#
# The 5-minute warning exists because staging starts at the timer's 21:55 and
# this script sleeps WARN_BEFORE seconds, so the download begins at 22:00 while
# the user has already been told.
#
# GUI is reached from the system service through the active logind session:
# notify-send for the warning, kdialog --yesno for the decision. If no active
# graphical session exists, semi mode never installs (no human to answer).
#
# Never installs unless the mode or the answer says so. Never reboots on its own
# except through update-now.sh after a successful transaction.
# =============================================================================
set -u

LOG=/var/log/garuda/update-prepare.log
STATE=/var/lib/garuda-restore
ENGINE=/usr/local/lib/garuda-restore/update-engine.sh
UPDATE_NOW=/usr/local/lib/garuda-restore/update-now.sh
CONF=/etc/garuda-restore/update.conf

MODE=semi
WARN_BEFORE=300
PROMPT_TIMEOUT=600
[ -r "$CONF" ] && . "$CONF"

[ "$(id -u)" -eq 0 ] || { echo "prepare-run: needs root" >&2; exit 1; }
mkdir -p "$STATE" /var/log/garuda
exec >>"$LOG" 2>&1
echo "=== $(date -Is) update run (MODE=$MODE WARN_BEFORE=$WARN_BEFORE) ==="

[ -x "$ENGINE" ] || { echo "FATAL: missing $ENGINE"; exit 1; }

# --- active graphical session (for notifications and the prompt) ------------
SESSION_USER=""
SESSION_ENV=()

detect_session() {
    local s t a u uid wd
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
        t=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
        a=$(loginctl show-session "$s" -p Active --value 2>/dev/null || true)
        u=$(loginctl show-session "$s" -p Name --value 2>/dev/null || true)
        case "${t:-}" in wayland|x11) ;; *) continue ;; esac
        [ "${a:-}" = "yes" ] || continue
        [ -n "${u:-}" ] || continue
        uid=$(id -u "$u" 2>/dev/null) || continue
        [ -d "/run/user/$uid" ] || continue
        SESSION_USER="$u"
        SESSION_ENV=(XDG_RUNTIME_DIR="/run/user/$uid"
                     DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
                     QT_QPA_PLATFORM=wayland)
        wd=$(ls /run/user/"$uid"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 || true)
        [ -n "${wd:-}" ] && SESSION_ENV+=(WAYLAND_DISPLAY="$(basename "$wd")")
        [ -n "${DISPLAY:-}" ] && SESSION_ENV+=(DISPLAY="$DISPLAY")
        echo "session: user=$u uid=$uid type=$t wayland=${wd:-none}"
        return 0
    done
    echo "session: none active"
    return 1
}

as_session() {
    [ -n "$SESSION_USER" ] || return 1
    runuser -u "$SESSION_USER" -- env "${SESSION_ENV[@]+"${SESSION_ENV[@]}"}" "$@"
}

notify() { # title body
    as_session notify-send --app-name="System update" --urgency="${3:-normal}" "$1" "$2" 2>/dev/null || true
}

ask_install() { # returns 0 = install now, 1 = later/no
    [ -n "$SESSION_USER" ] || { echo "prompt: no session - not applying"; return 1; }
    if as_session timeout "$PROMPT_TIMEOUT" kdialog --title "System update" \
            --yes-label "Install now" --no-label "Later" \
            --geometry 760x240 --yesno "$1"; then
        echo "prompt: user chose INSTALL"
        return 0
    fi
    echo "prompt: later / timeout / dismissed - staged only"
    return 1
}

status() { # phase rc pending cache snapshot news
    printf 'time=%s phase=%s rc=%s pending=%s cache=%s snapshot=%s news=%s mode=%s\n' \
        "$(date -Is)" "$1" "$2" "$3" "$4" "$5" "$6" "$MODE" > "$STATE/prepare.status"
}

# --- 1. warn -----------------------------------------------------------------
if [ "${WARN_BEFORE:-0}" -gt 0 ]; then
    notify "System update in $((WARN_BEFORE / 60)) minutes" \
           "Package staging starts at $(date -d "+${WARN_BEFORE} seconds" +%H:%M). The desktop stays usable." \
           low
    echo "warned: staging in ${WARN_BEFORE}s"
    sleep "$WARN_BEFORE"
fi

# --- 2. upstream advisories ---------------------------------------------------
news=0
feed=$(curl -fsS --max-time 20 https://archlinux.org/feeds/news/ 2>/dev/null || true)
if [ -n "${feed:-}" ]; then
    news=$(printf '%s' "$feed" | grep -c '<item>' || true)
    prev=$(cat "$STATE/news.count" 2>/dev/null || echo 0)
    case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
    if [ "$news" -gt "$prev" ]; then
        echo "ADVISORY: $((news - prev)) new Arch news item(s) since the last run"
        printf '%s' "$feed" | grep -o '<item><title>[^<]*' | head -3 | sed 's|<item><title>|  news: |'
    fi
    printf '%s\n' "$news" > "$STATE/news.count"
else
    echo "advisory: could not fetch the Arch news feed (network?)"
fi

# --- 3. stage ----------------------------------------------------------------
detect_session
notify "Staging system updates" "Downloading packages; the desktop stays usable." low
"$ENGINE" prepare
rc=$?

pending=$(pacman -Qu 2>/dev/null | wc -l)
cache=$(du -sh /var/cache/pacman/pkg 2>/dev/null | cut -f1)
snap=$(snapper -c root list 2>/dev/null | tail -1 | awk '{print $1}')
status prepare "$rc" "$pending" "$cache" "${snap:-n/a}" "$news"
echo "=== prepare rc=$rc pending=$pending cache=$cache snapshot=${snap:-n/a} ==="

[ "$rc" -eq 0 ] || { notify "Update staging failed" "See /var/log/garuda/update-prepare.log" critical; exit "$rc"; }
[ "$pending" -gt 0 ] || { echo "nothing to apply"; notify "System is up to date" "No packages to install." low; exit 0; }

# --- 4. decide + apply -------------------------------------------------------
case "$MODE" in
    auto)
        echo "mode=auto: applying"
        notice="System update ready"; body="${pending} packages will install now. The desktop will close and the machine will reboot."
        notify "$notice" "$body"
        if [ -x "$UPDATE_NOW" ]; then
            "$UPDATE_NOW"; arc=$?
            status handover "$arc" "$pending" "$cache" "${snap:-n/a}" "$news"
            echo "=== handover rc=$arc; install result: /var/log/garuda/update-now-run.log ==="
            exit "$arc"
        fi
        echo "FATAL: missing $UPDATE_NOW"; exit 1
        ;;
    semi)
        body="${pending} packages are staged (cache ${cache}). Install now? The desktop will close and the machine will reboot. Choosing Later leaves everything downloaded and installs nothing."
        if ask_install "$body"; then
            if [ -x "$UPDATE_NOW" ]; then
                "$UPDATE_NOW"; arc=$?
                status handover "$arc" "$pending" "$cache" "${snap:-n/a}" "$news"
                echo "=== handover rc=$arc; install result: /var/log/garuda/update-now-run.log ==="
                exit "$arc"
            fi
            echo "FATAL: missing $UPDATE_NOW"; exit 1
        fi
        # start the reminder cadence: first reminder in REMIND_FIRST (1 h), then every 3 h
        printf 'LAST_PROMPT=%s\nDECLINES=0\n' "$(date +%s)" > "$STATE/prompt.state"
        status staged 0 "$pending" "$cache" "${snap:-n/a}" "$news"
        notify "Updates staged" "${pending} packages are ready; I will ask again in an hour." normal
        exit 0
        ;;
    stage)
        echo "mode=stage: staging only"
        status staged 0 "$pending" "$cache" "${snap:-n/a}" "$news"
        notify "Updates staged" "${pending} packages are ready. Apply with update-now.sh." low
        exit 0
        ;;
    *)
        echo "FATAL: unknown MODE=$MODE (auto|semi|stage)"; exit 1
        ;;
esac
