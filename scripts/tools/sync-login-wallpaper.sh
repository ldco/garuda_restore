#!/usr/bin/env bash
# =============================================================================
# sync-login-wallpaper.sh - the login screen uses the desktop wallpaper
# =============================================================================
# Garuda's Plasma greeter (plasmalogin) ships with its own wallpaper, set in
#   /etc/plasmalogin.conf  ->  [Greeter][Wallpaper][org.kde.image][General]
#                              Image=file:///var/lib/plasmalogin/wallpapers/Malefor.jpg
# and nothing in System Settings changes it: the greeter is root's session, not
# yours. This copies YOUR current Plasma wallpaper into the greeter's directory
# (a local copy - the greeter must not depend on an external drive being mounted
# at boot) and points the greeter config at it.
#
# Usage:
#   sudo ./scripts/tools/sync-login-wallpaper.sh                  # sync once
#   sudo ./scripts/tools/sync-login-wallpaper.sh --image PATH     # use this file
#   sudo ./scripts/tools/sync-login-wallpaper.sh --install-watch  # keep it in sync
#   ./scripts/tools/sync-login-wallpaper.sh --dry-run             # plan only
#   sudo ./scripts/tools/sync-login-wallpaper.sh --apply          # restart the greeter
#
# --install-watch adds garuda-login-wallpaper.path/.service, which re-runs this
# script whenever Plasma rewrites the wallpaper config, so the login screen
# follows the desktop from then on.
#
# The greeter picks the new image up at the next login screen (logout or reboot).
# --apply restarts plasmalogin, which ENDS THE CURRENT SESSION - use it from a
# TTY, not from inside the session you are working in.
# =============================================================================
set -Eeuo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
GREETER_CONF=/etc/plasmalogin.conf
WALL_DIR=/var/lib/plasmalogin/wallpapers
DEST="$WALL_DIR/desktop.jpg"
STATE_FILE=/var/lib/garuda-restore/login-wallpaper.state
INSTALLED=/usr/local/lib/garuda-restore/sync-login-wallpaper.sh
TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
APPLETSRC="$TARGET_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
SECTION='[Greeter][Wallpaper][org.kde.image][General]'

DRY_RUN=0
APPLY=0
WATCH=0
FORCE=0
IMAGE_ARG=""

say()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)       DRY_RUN=1 ;;
        --apply)         APPLY=1 ;;
        --install-watch) WATCH=1 ;;
        --force)         FORCE=1 ;;
        --image)         shift; IMAGE_ARG="${1:-}" ;;
        -h|--help)       sed -n '2,31p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

[ "$DRY_RUN" -eq 1 ] || [ "$(id -u)" -eq 0 ] || die "run this with sudo (or use --dry-run)"
[ -r "$GREETER_CONF" ] || die "$GREETER_CONF not found - is plasmalogin the display manager? (check: systemctl status display-manager)"

# --- what wallpaper does the desktop use right now? -------------------------
resolve_source() {
    local raw
    if [ -n "$IMAGE_ARG" ]; then
        printf '%s' "$IMAGE_ARG"
        return 0
    fi
    [ -r "$APPLETSRC" ] || die "cannot read $APPLETSRC (is $TARGET_USER logged in with Plasma?)"
    raw="$(grep -o 'Image=file://[^[:space:]]*' "$APPLETSRC" | tail -1 | sed 's|^Image=file://||' || true)"
    if [ -z "$raw" ]; then
        raw="$(grep -o 'Image=/[^[:space:]]*' "$APPLETSRC" | tail -1 | sed 's|^Image=||' || true)"
    fi
    [ -n "$raw" ] || die "no wallpaper found in $APPLETSRC - pass --image PATH"
    # KConfig stores URLs: %20 for spaces, etc.
    printf '%b' "${raw//%/\\x}"
}

src="$(resolve_source)"
[ -r "$src" ] || die "wallpaper not readable: $src"

say "desktop wallpaper"
info "user : $TARGET_USER"
info "image: $src"
info "size : $(du -h "$src" 2>/dev/null | cut -f1)"

last="$(cat "$STATE_FILE" 2>/dev/null || true)"
if [ "$FORCE" -eq 0 ] && [ "$last" = "$src" ] && [ -s "$DEST" ] && [ "$WATCH" -eq 0 ]; then
    say "login wallpaper is already in sync with $src"
    exit 0
fi

# --- copy it somewhere the greeter can always read --------------------------
say "installing a local copy for the greeter"
info "dest : $DEST"
if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] convert + install the image"
else
    install -d -m 755 "$WALL_DIR"
    if command -v magick >/dev/null 2>&1; then
        magick "$src" -auto-orient -depth 8 -strip -resize '3840x2160>' \
            -quality 92 "$DEST.tmp.jpg"
        mv -f "$DEST.tmp.jpg" "$DEST"
    elif command -v convert >/dev/null 2>&1; then
        convert "$src" -auto-orient -depth 8 -strip -resize '3840x2160>' \
            -quality 92 "$DEST.tmp.jpg"
        mv -f "$DEST.tmp.jpg" "$DEST"
    else
        cp -f "$src" "$DEST"
    fi
    chmod 644 "$DEST"
    info "written: $(du -h "$DEST" | cut -f1)"
fi

# --- point the greeter at it ------------------------------------------------
say "greeter configuration"
info "file : $GREETER_CONF"
if [ "$DRY_RUN" -eq 1 ]; then
    info "[dry-run] set Image=file://$DEST in $SECTION"
else
    cp -a "$GREETER_CONF" "$GREETER_CONF.bak-$(date +%Y%m%d-%H%M%S)"
    if grep -qF "$SECTION" "$GREETER_CONF"; then
        sed -i "s|^Image=.*|Image=file://$DEST|" "$GREETER_CONF"
    else
        printf '\n%s\nImage=file://%s\n' "$SECTION" "$DEST" >> "$GREETER_CONF"
    fi
    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$src" > "$STATE_FILE"
    grep -A1 -F "$SECTION" "$GREETER_CONF" | sed 's/^/    /'
    info "(previous file kept as $GREETER_CONF.bak-*)"
fi

# --- optional: keep it in sync automatically --------------------------------
if [ "$WATCH" -eq 1 ]; then
    say "install the watcher (login screen follows the desktop)"
    if [ "$DRY_RUN" -eq 1 ]; then
        info "[dry-run] install $INSTALLED + garuda-login-wallpaper.path/.service"
    else
        install -Dm755 "$SELF" "$INSTALLED"
        cat > /etc/systemd/system/garuda-login-wallpaper.service <<UNIT
[Unit]
Description=Sync the login screen wallpaper with the desktop wallpaper

[Service]
Type=oneshot
ExecStart=$INSTALLED
UNIT
        cat > /etc/systemd/system/garuda-login-wallpaper.path <<UNIT
[Unit]
Description=Watch the Plasma wallpaper configuration

[Path]
PathChanged=$APPLETSRC
Unit=garuda-login-wallpaper.service

[Install]
WantedBy=paths.target
UNIT
        systemctl --no-ask-password daemon-reload
        systemctl --no-ask-password enable --now garuda-login-wallpaper.path
        info "watcher: $(systemctl is-active garuda-login-wallpaper.path) / $(systemctl is-enabled garuda-login-wallpaper.path)"
    fi
fi

# --- optional: apply immediately -------------------------------------------
if [ "$APPLY" -eq 1 ]; then
    say "restarting plasmalogin"
    info "WARNING: this ends the current graphical session"
    [ "$DRY_RUN" -eq 1 ] || systemctl restart plasmalogin
else
    say "done"
    info "the new image appears at the next login screen (logout or reboot)"
    info "to apply now from a TTY: sudo systemctl restart plasmalogin"
fi
exit 0
