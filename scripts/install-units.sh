#!/bin/bash
# ============================================================================
# INSTALL UNITS - deploy the user systemd units and the scripts they call
# ============================================================================
# The repo ships systemd/*.service units whose ExecStart points at
#   ~/.local/share/garuda-backup-scripts/<name>.sh
# but nothing ever created that directory. Result: every such unit failed with
# status=127 (command not found) forever, silently, on a 15-minute timer.
#
# This installs exactly the scripts the shipped units reference, then installs
# the units themselves, then reloads systemd. Idempotent.
#
# No root required (user units + ~/.local/share only).
# ============================================================================
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.local/share/garuda-backup-scripts"
UNITDEST="$HOME/.config/systemd/user"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "$DEST" "$UNITDEST"

echo "repo:      $REPO"
echo "scripts:   $DEST"
echo "units:     $UNITDEST"
echo

# ---------------------------------------------------------------------------
# 1. Determine which scripts the shipped units actually reference.
# ---------------------------------------------------------------------------
needed=()
for u in "$REPO"/systemd/*; do
    [ -f "$u" ] || continue
    while read -r s; do
        [ -n "$s" ] && needed+=("$s")
    done < <(grep -oE 'garuda-backup-scripts/[A-Za-z0-9._-]+\.sh' "$u" 2>/dev/null | sed 's#.*/##' | sort -u)
done
# dedupe
mapfile -t needed < <(printf '%s\n' "${needed[@]:-}" | grep -v '^$' | sort -u)

if [ "${#needed[@]}" -eq 0 ]; then
    echo "no unit references a deployed script; nothing to install"
else
    # -----------------------------------------------------------------------
    # 2. Deploy those scripts.
    # -----------------------------------------------------------------------
    for s in "${needed[@]}"; do
        src="$REPO/scripts/$s"
        if [ ! -f "$src" ]; then
            echo "  ! $s referenced by a unit but missing from $REPO/scripts/"
            continue
        fi
        install -m 755 "$src" "$DEST/$s"
        echo "  ✓ script $s"
    done
fi

# ---------------------------------------------------------------------------
# 3. Install the units. Refuse to install a unit whose script is still absent.
# ---------------------------------------------------------------------------
for u in "$REPO"/systemd/*; do
    [ -f "$u" ] || continue
    b="$(basename "$u")"
    ref="$(grep -oE 'garuda-backup-scripts/[A-Za-z0-9._-]+\.sh' "$u" 2>/dev/null | head -1 | sed 's#.*/##' || true)"
    if [ -n "$ref" ] && [ ! -f "$DEST/$ref" ]; then
        echo "  skip $b (deployed script $ref not available)"
        continue
    fi
    # A unit targeting a SYSTEM target does not belong in the user manager - it
    # would be enabled but never triggered, and cannot write sysfs. Installing
    # one here is worse than skipping it, so route it to the system dir.
    if grep -qE '^WantedBy=.*(multi-user|basic|system)\.target' "$u"; then
        echo "  skip $b (system unit - install with: sudo install -m644 '$u' /etc/systemd/system/ && sudo systemctl enable $(basename "$u" .service))"
        continue
    fi
    if [ -f "$UNITDEST/$b" ] && cmp -s "$u" "$UNITDEST/$b"; then
        echo "  = unit $b (unchanged)"
        continue
    fi
    [ -f "$UNITDEST/$b" ] && cp -a "$UNITDEST/$b" "$UNITDEST/$b.bak-$STAMP"
    install -m 644 "$u" "$UNITDEST/$b"
    echo "  ✓ unit $b"
done

systemctl --user daemon-reload

# ---------------------------------------------------------------------------
# 4. Enable timers, and long-running services.
# ---------------------------------------------------------------------------
for t in "$REPO"/systemd/*.timer; do
    [ -f "$t" ] || continue
    b="$(basename "$t")"
    systemctl --user enable --now "$b" >/dev/null 2>&1 && echo "  enabled timer $b"
done
for s in "$REPO"/systemd/*.service; do
    [ -f "$s" ] || continue
    b="$(basename "$s")"
    # oneshot jobs are driven by their timer; long-running ones are enabled
    if grep -q 'Type=simple' "$s"; then
        systemctl --user enable --now "$b" >/dev/null 2>&1 && echo "  enabled service $b"
    else
        systemctl --user enable "$b" >/dev/null 2>&1 && echo "  enabled service $b"
    fi
done

echo
echo "--- failing user units after install ---"
fail="$(systemctl --user list-units --state=failed --no-legend --no-pager 2>/dev/null \
        | grep -viE 'bluedevilwizard|libinput' || true)"
if [ -z "$fail" ]; then
    echo "  none (bluedevil wizard / libinput failures are unrelated app jobs)"
else
    echo "$fail"
fi
