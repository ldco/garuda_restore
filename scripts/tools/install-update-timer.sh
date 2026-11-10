#!/usr/bin/env bash
# =============================================================================
# install-update-timer.sh - install the weekly off-peak upgrade staging
# =============================================================================
# Installs update-engine.sh + prepare-run.sh into /usr/local/lib/garuda-restore
# (so the timer never depends on this repo's external drive), then installs and
# enables update-prepare.timer. The timer only DOWNLOADS: it never installs,
# upgrades. Applying stays a deliberate, gated action (update-now.sh).
#
#   sudo ./scripts/tools/install-update-timer.sh              # install + enable
#   ./scripts/tools/install-update-timer.sh --dry-run         # show the plan
#   sudo ./scripts/tools/install-update-timer.sh --uninstall  # remove units
# =============================================================================
set -Eeuo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/../.." && pwd)"
DEST=/usr/local/lib/garuda-restore
UNITD=/etc/systemd/system
DRY_RUN=0
MODE=install

say()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
is_root() { [ "$(id -u)" -eq 0 ]; }
run() { if [ "$DRY_RUN" -eq 1 ]; then printf '[dry-run] %s\n' "$*"; else "$@"; fi }

for arg in "$@"; do
    case "$arg" in
        --dry-run)   DRY_RUN=1 ;;
        --uninstall) MODE=uninstall ;;
        -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

# --dry-run may run unprivileged; everything else must be root
[ "$DRY_RUN" -eq 1 ] || is_root || die "run this with sudo"

install_timer() {
    say "staging the update tools in $DEST"
    run install -Dm755 "$SELF_DIR/update-engine.sh" "$DEST/update-engine.sh"
    run install -Dm755 "$SELF_DIR/update-now.sh"    "$DEST/update-now.sh"
    run install -Dm755 "$SELF_DIR/prepare-run.sh"   "$DEST/prepare-run.sh"
    run install -Dm755 "$SELF_DIR/prompt-run.sh"    "$DEST/prompt-run.sh"
    run install -Dm755 "$SELF_DIR/maintenance-run.sh" "$DEST/maintenance-run.sh"
    run install -Dm755 "$SELF_DIR/update-alarm.sh"    "$DEST/update-alarm.sh"
    run install -Dm644 "$REPO/systemd/garuda-update-now.service" \
        "$DEST/garuda-update-now.service"

    say "configuration (MODE=semi: warn, stage, ask)"
    if [ -e /etc/garuda-restore/update.conf ] && [ "$DRY_RUN" -eq 0 ]; then
        info "keeping existing /etc/garuda-restore/update.conf"
    else
        run mkdir -p /etc/garuda-restore
        run sh -c 'printf "%s
" "# MODE: semi  = warn, stage, then ask (GUI yes/no) before applying" "#       auto  = warn, stage, apply and reboot without asking" "#       stage = warn, stage only" "MODE=semi" "" "# Seconds between the 21:55 warning and the start of staging." "WARN_BEFORE=300" "" "# Seconds the GUI prompt waits before treating silence as Later." "PROMPT_TIMEOUT=600" "" "# Reminder cadence after a decline/timeout: first in 1 h, then every 3 h," "# until INSTALL or until the next Friday run." "REMIND_FIRST=3600" "REMIND_EVERY=10800" "" "# Post-update maintenance (first boot after an applied update)." "# cache keeps KEEP_PACKAGES versions; orphans are listed, not removed." "MAINTENANCE=1" "KEEP_PACKAGES=2" "JOURNAL_MAX=500M" "FSTRIM=1" "REMOVE_ORPHANS=0" "HEALTH_FIX=0" > /etc/garuda-restore/update.conf'
    fi

    say "installing the units"
    run install -m644 "$REPO/systemd/update-prepare.service" "$UNITD/update-prepare.service"
    run install -m644 "$REPO/systemd/update-prepare.timer"   "$UNITD/update-prepare.timer"
    run install -m644 "$REPO/systemd/update-prompt.service"  "$UNITD/update-prompt.service"
    run install -m644 "$REPO/systemd/update-prompt.timer"    "$UNITD/update-prompt.timer"
    run install -m644 "$REPO/systemd/update-maintenance.service" "$UNITD/update-maintenance.service"
    run install -m644 "$REPO/systemd/garuda-update-alarm@.service" "$UNITD/garuda-update-alarm@.service"

    say "enabling the weekly timer"
    run systemctl --no-ask-password daemon-reload
    run systemctl --no-ask-password enable --now update-prepare.timer
    run systemctl --no-ask-password enable --now update-prompt.timer
    run systemctl --no-ask-password enable update-maintenance.service

    # Deliberately no maintenance kick here: paccache over a 23 GiB cache plus
    # fstrim on a 477 GiB btrfs takes minutes, and doing it inside this script
    # made `stabilize-once.sh` look frozen at "1/5" (2026-11-11). The one-shot
    # setup runs it in its own step, with output and a message first; a plain
    # `install-update-timer.sh` leaves the flag to the next boot.

    if [ "$DRY_RUN" -eq 0 ]; then
        printf '\n'
        systemctl list-timers update-prepare.timer update-prompt.timer --no-pager || true
        printf '\nRun a staging pass now:  sudo systemctl start update-prepare.service\n'
        printf 'Status file:             /var/lib/garuda-restore/prepare.status\n'
        printf 'Log:                     /var/log/garuda/update-prepare.log\n'
    fi
}

uninstall_timer() {
    say "disabling and removing the units"
    run systemctl --no-ask-password disable --now update-prepare.timer update-prompt.timer || true
    run systemctl --no-ask-password stop update-prepare.service update-prompt.service || true
    run systemctl --no-ask-password disable update-maintenance.service || true
    run rm -f "$UNITD/update-prepare.timer" "$UNITD/update-prepare.service" \
               "$UNITD/update-prompt.timer" "$UNITD/update-prompt.service" \
               "$UNITD/update-maintenance.service"
    run systemctl --no-ask-password daemon-reload
    run rm -f "$DEST/prepare-run.sh" "$DEST/prompt-run.sh" "$DEST/maintenance-run.sh"
    say "removed the units and prepare-run.sh (update-engine.sh kept in $DEST)"
}

case "$MODE" in
    install)   install_timer ;;
    uninstall) uninstall_timer ;;
esac
