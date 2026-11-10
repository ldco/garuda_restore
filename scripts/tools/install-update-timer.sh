#!/usr/bin/env bash
# =============================================================================
# install-update-timer.sh - install the weekly off-peak upgrade staging
# =============================================================================
# Installs update-engine.sh + prepare-run.sh into /usr/local/lib/garuda-restore
# (so the timer never depends on this repo's external drive), then installs and
# enables update-prepare.timer. The timer only DOWNLOADS: it never installs,
# upgrades or reboots. Applying stays a deliberate TTY action (update-now.sh).
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

    say "configuration (MODE=semi: warn, stage, ask)"
    if [ -e /etc/garuda-restore/update.conf ] && [ "$DRY_RUN" -eq 0 ]; then
        info "keeping existing /etc/garuda-restore/update.conf"
    else
        run mkdir -p /etc/garuda-restore
        run sh -c 'printf "%s
" "# MODE: semi  = warn, stage, then ask (GUI yes/no) before applying" "#       auto  = warn, stage, apply and reboot without asking" "#       stage = warn, stage only" "MODE=semi" "" "# Seconds between the 21:55 warning and the start of staging." "WARN_BEFORE=300" "" "# Seconds the GUI prompt waits before treating silence as Later." "PROMPT_TIMEOUT=600" > /etc/garuda-restore/update.conf'
    fi

    say "installing the units"
    run install -m644 "$SELF_DIR/../systemd/update-prepare.service" "$UNITD/update-prepare.service"
    run install -m644 "$SELF_DIR/../systemd/update-prepare.timer"   "$UNITD/update-prepare.timer"

    say "enabling the weekly timer"
    run systemctl daemon-reload
    run systemctl enable --now update-prepare.timer

    if [ "$DRY_RUN" -eq 0 ]; then
        printf '\n'
        systemctl list-timers update-prepare.timer --no-pager || true
        printf '\nRun a staging pass now:  sudo systemctl start update-prepare.service\n'
        printf 'Status file:             /var/lib/garuda-restore/prepare.status\n'
        printf 'Log:                     /var/log/garuda/update-prepare.log\n'
    fi
}

uninstall_timer() {
    say "disabling and removing the units"
    run systemctl disable --now update-prepare.timer || true
    run systemctl stop update-prepare.service || true
    run rm -f "$UNITD/update-prepare.timer" "$UNITD/update-prepare.service"
    run systemctl daemon-reload
    run rm -f "$DEST/prepare-run.sh"
    say "removed the units and prepare-run.sh (update-engine.sh kept in $DEST)"
}

case "$MODE" in
    install)   install_timer ;;
    uninstall) uninstall_timer ;;
esac
