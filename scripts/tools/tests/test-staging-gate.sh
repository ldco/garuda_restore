#!/usr/bin/env bash
# =============================================================================
# test-staging-gate.sh - the offline staging gate, tested without root
# =============================================================================
# Regression tests for the 2026-11-10/11 failures:
#   * update-now.sh must refuse to stop the desktop when the staged cache is
#     incomplete or stale (2026-11-10: `pacman -Sc` purged it and the "offline"
#     install re-downloaded 8.7 GiB on tty1);
#   * the engine's --check-cache path must never need the network;
#   * an empty update queue (`pacman -Qu` exits 1) must not abort anything
#     (2026-11-11: it killed `clean` and logged a bogus ERROR after a good run);
#   * the generated runner must stay unattended: no login prompt on tty1, and a
#     separate unit restores the desktop on failure.
#
# Everything runs as the invoking user (the checks are read-only), uses
# temporary directories, and stubs `pacman` for the fixtures - so the suite
# gives the same result on a machine with pending updates and on a fully
# updated one.
# Usage: ./scripts/tools/tests/test-staging-gate.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
ENGINE="$REPO/scripts/tools/update-engine.sh"
UPDATE_NOW="$REPO/scripts/tools/update-now.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

mkdir -p "$TMP/bin" "$TMP/mark" "$TMP/empty" "$TMP/full" "$TMP/log" "$TMP/state"

# --- pacman stub: fixture target list + pending count ----------------------
cat > "$TMP/bin/pacman" <<'STUB'
#!/bin/bash
case " $* " in
    *" -Sup "*)
        [ -n "${STUB_TARGETS:-}" ] && [ -r "${STUB_TARGETS:-}" ] && cat "$STUB_TARGETS"
        exit 0
        ;;
    *" -Qu "*)
        # Real pacman exits 1 when the queue is empty; that must not abort the
        # caller. Test 5/6 rely on this.
        if [ -n "${STUB_PENDING:-}" ]; then
            for ((i = 1; i <= STUB_PENDING; i++)); do printf 'pkg%s\n' "$i"; done
        fi
        exit "${STUB_QU_RC:-0}"
        ;;
esac
exit 0
STUB
chmod 755 "$TMP/bin/pacman"

# --- markers: did update-now reach the desktop-stopping code? --------------
for c in systemctl chvt; do
    printf '#!/bin/bash\ntouch "%s/marker-%s"\nexit 0\n' "$TMP" "$c" > "$TMP/mark/$c"
    chmod 755 "$TMP/mark/$c"
done

# --- fixture: three targets, epoch in the version, as pacman prints them ---
printf 'alpha 1.0-1 x86_64\nbeta 2.0-1 x86_64\ngamma 1:3.0-1 any\n' > "$TMP/targets"
: > "$TMP/no-targets"
touch "$TMP/full/alpha-1.0-1-x86_64.pkg.tar.zst" \
      "$TMP/full/beta-2.0-1-x86_64.pkg.tar.zst" \
      "$TMP/full/gamma-1:3.0-1-any.pkg.tar.zst"

run_engine() { # $1 = cache dir, $2 = state dir, extra assignments before
    env PATH="$TMP/bin:$PATH" STUB_TARGETS="$TMP/targets" STUB_PENDING=3 \
        GR_CACHE_DIR="$1" GR_STATE_DIR="$2" GR_LOG_DIR="$TMP/log" \
        "$ENGINE" install --offline --check-cache 2>&1
}

printf 'staging gate\n'

# 1. Complete fixture cache -> pass.
out="$(run_engine "$TMP/full" "$TMP/state")"; rc=$?
check "complete fixture cache passes" '[ "$rc" -eq 0 ]'
check "complete fixture cache counts 3 packages" 'grep -q "all 3 packages" <<<"$out"'

# 2. One package missing -> fail, and only that name is reported.
mv "$TMP/full/beta-2.0-1-x86_64.pkg.tar.zst" "$TMP/beta.off"
out="$(run_engine "$TMP/full" "$TMP/state")"; rc=$?
check "one missing package fails the gate" '[ "$rc" -ne 0 ]'
check "the missing package is named" 'grep -q "missing: beta-2.0-1" <<<"$out"'
check "present packages are not reported missing" '! grep -q "missing: alpha" <<<"$out"'
mv "$TMP/beta.off" "$TMP/full/beta-2.0-1-x86_64.pkg.tar.zst"

# 3. Manifest from an older staging (the sync DB moved) -> stale refusal.
mkdir -p "$TMP/state3"
printf 'STAMP=2026-11-11T00:49:15+03:00\nCACHE=%s\nTARGETS=2\nSHA256=deadbeef\n' "$TMP/full" \
    > "$TMP/state3/staged.manifest"
out="$(run_engine "$TMP/full" "$TMP/state3")"; rc=$?
check "stale manifest fails the gate" '[ "$rc" -ne 0 ]'
check "stale manifest is reported as STALE" 'grep -q "STALE" <<<"$out"'

# 4. Pending upgrades but no resolvable targets -> stale databases, refuse.
out="$(env PATH="$TMP/bin:$PATH" STUB_TARGETS="$TMP/no-targets" STUB_PENDING=7 \
       GR_CACHE_DIR="$TMP/full" GR_STATE_DIR="$TMP/state4" GR_LOG_DIR="$TMP/log" \
       "$ENGINE" install --offline --check-cache 2>&1)"; rc=$?
check "pending upgrades with no targets fail the gate" '[ "$rc" -ne 0 ]'
check "the stale databases are named" 'grep -q "databases are stale" <<<"$out"'

# 5. Empty update queue (pacman -Qu exit 1) -> pass, "nothing staged".
out="$(env PATH="$TMP/bin:$PATH" STUB_TARGETS="$TMP/no-targets" STUB_QU_RC=1 \
       GR_CACHE_DIR="$TMP/empty" GR_STATE_DIR="$TMP/state5" GR_LOG_DIR="$TMP/log" \
       "$ENGINE" install --offline --check-cache 2>&1)"; rc=$?
check "empty queue (pacman -Qu exit 1) passes the check" '[ "$rc" -eq 0 ]'
check "empty queue is reported as nothing staged" 'grep -q "nothing staged" <<<"$out"'

# 6. A manifest left over from an installed update is consumed, not "stale".
mkdir -p "$TMP/state5"
printf 'STAMP=2026-11-11T01:15:00+03:00\nCACHE=%s\nTARGETS=469\nSHA256=deadbeef\n' "$TMP/full" \
    > "$TMP/state5/staged.manifest"
out="$(env PATH="$TMP/bin:$PATH" STUB_TARGETS="$TMP/no-targets" STUB_QU_RC=1 \
       GR_CACHE_DIR="$TMP/empty" GR_STATE_DIR="$TMP/state5" GR_LOG_DIR="$TMP/log" \
       "$ENGINE" install --offline --check-cache 2>&1)"; rc=$?
check "a spent manifest is not reported as stale" '[ "$rc" -eq 0 ]'
check "the spent manifest is reported as installed" 'grep -q "staged set was installed" <<<"$out"'

# 7. Empty cache with a real target list -> fast, loud, network-free refusal.
start=$(date +%s%N)
out="$(run_engine "$TMP/empty" "$TMP/state7")"; rc=$?
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
check "incomplete cache exits non-zero" '[ "$rc" -ne 0 ]'
check "incomplete cache names a missing package" 'grep -q "missing: alpha-1.0-1" <<<"$out"'
check "incomplete cache says nothing was downloaded" 'grep -q "nothing was downloaded" <<<"$out"'
check "incomplete cache fails in under 5 s (${elapsed_ms} ms)" '[ "$elapsed_ms" -lt 5000 ]'

# 8. No network at all: inside an empty network namespace the check still
#    reaches the same verdict (nothing to resolve, nothing to fetch).
if command -v unshare >/dev/null 2>&1; then
    out="$(PATH="$TMP/bin:$PATH" STUB_TARGETS="$TMP/targets" STUB_PENDING=3 \
           GR_CACHE_DIR="$TMP/full" GR_STATE_DIR="$TMP/state" GR_LOG_DIR="$TMP/log" \
           unshare -rn "$ENGINE" install --offline --check-cache 2>&1)"; rc=$?
    check "complete cache passes with no network namespace" '[ "$rc" -eq 0 ]'
    out="$(PATH="$TMP/bin:$PATH" STUB_TARGETS="$TMP/targets" STUB_PENDING=3 \
           GR_CACHE_DIR="$TMP/empty" GR_STATE_DIR="$TMP/state" GR_LOG_DIR="$TMP/log" \
           unshare -rn "$ENGINE" install --offline --check-cache 2>&1)"; rc=$?
    check "incomplete cache refuses with no network namespace" '[ "$rc" -ne 0 ]'
else
    printf '  skip unshare not available\n'
fi

# 9. update-now.sh --dry-run with an incomplete cache: refuses, and nothing is
#    stopped (no systemctl/chvt marker), exit 1.
rm -f "$TMP"/marker-*
out="$(PATH="$TMP/mark:$TMP/bin:$PATH" STUB_TARGETS="$TMP/targets" STUB_PENDING=3 \
       GR_CACHE_DIR="$TMP/empty" GR_STATE_DIR="$TMP/state9" GR_LOG_DIR="$TMP/log" \
       "$UPDATE_NOW" --dry-run 2>&1)"
rc=$?
check "update-now --dry-run refuses an incomplete cache" '[ "$rc" -ne 0 ]'
check "update-now says the desktop was not stopped" 'grep -q "desktop was NOT stopped" <<<"$out"'
check "update-now did not call systemctl" '[ ! -e "$TMP/marker-systemctl" ]'
check "update-now did not call chvt" '[ ! -e "$TMP/marker-chvt" ]'

# 10. update-now.sh --dry-run with a complete cache: passes, prints the unit,
#     still stops nothing.
out="$(PATH="$TMP/mark:$TMP/bin:$PATH" STUB_TARGETS="$TMP/targets" STUB_PENDING=3 \
       GR_CACHE_DIR="$TMP/full" GR_STATE_DIR="$TMP/state10" GR_LOG_DIR="$TMP/log" \
       "$UPDATE_NOW" --dry-run 2>&1)"
rc=$?
check "update-now --dry-run passes on a complete cache" '[ "$rc" -eq 0 ]'
check "update-now --dry-run shows the unit" 'grep -q "Conflicts=graphical.target" <<<"$out"'
check "update-now --dry-run stopped nothing" '[ ! -e "$TMP/marker-systemctl" ]'

# 11. The real `status` mode on this machine: read-only, must not abort when
#     the update queue is empty (pacman -Qu exit 1).
out="$("$ENGINE" status 2>&1)"; rc=$?
check "status works with a real (possibly empty) queue" '[ "$rc" -eq 0 ]'
check "status does not report a command failure" '! grep -q "ERROR: command failed" <<<"$out"'

# 12. The generated scripts must parse and keep the install unattended.
sed -n "/cat > \"\$RUNNER\" <<'RUNNER_EOF'/,/^RUNNER_EOF$/p" "$UPDATE_NOW" | sed '1d;$d' > "$TMP/runner.sh"
sed -n "/cat > \"\$RESTORE\" <<'RESTORE_EOF'/,/^RESTORE_EOF$/p" "$UPDATE_NOW" | sed '1d;$d' > "$TMP/restore.sh"
check "the generated runner is not empty" '[ -s "$TMP/runner.sh" ]'
check "the generated restore script is not empty" '[ -s "$TMP/restore.sh" ]'
check "the runner parses" 'bash -n "$TMP/runner.sh"'
check "the restore script parses" 'bash -n "$TMP/restore.sh"'
check "the runner takes over tty1 (no login prompt)" 'grep -q "getty@tty1" "$TMP/runner.sh"'
check "the runner mirrors output to the console" 'grep -q "/dev/tty1" "$TMP/runner.sh"'
check "the failure path restores the desktop from its own unit" 'grep -q "systemd-run --collect --no-block --unit=garuda-update-restore" "$TMP/runner.sh"'
check "the restore script notifies the user" 'grep -q "notify-send" "$TMP/restore.sh"'

# 13. The one-shot setup script: --dry-run is root-free, names every step, and
#     the timer installer resolves real unit sources - its paths pointed at
#     scripts/systemd (nonexistent), so no unit had ever been installed.
out="$("$REPO/scripts/tools/stabilize-once.sh" --dry-run 2>&1)"; rc=$?
check "stabilize-once --dry-run works without root" '[ "$rc" -eq 0 ]'
check "it covers the weekly timer stack" 'grep -q "update-prepare.timer" <<<"$out"'
check "it covers the paru release-age knob" 'grep -q "MinimumReleaseAge = 3d" <<<"$out"'
check "it covers the maintenance run" 'grep -q "update-maintenance" <<<"$out"'
check "it covers stale cache leftovers" 'grep -q "4/5 cache leftovers" <<<"$out"'
check "it prints what stays manual" 'grep -q "paru -Sua" <<<"$out"'

out="$("$REPO/scripts/tools/install-update-timer.sh" --dry-run 2>&1)"
sources="$(grep -oE '/[^ ]*/systemd/(update|garuda)[^ ]*\.(service|timer)' <<<"$out" | sort -u)"
check "the timer installer references unit sources" '[ -n "$sources" ]'
missing=0
while IFS= read -r f; do
    [ -n "$f" ] && [ -r "$f" ] || missing=$((missing + 1))
done <<<"$sources"
check "every referenced unit source exists ($missing missing)" '[ "$missing" -eq 0 ]'

# 14. stabilize-once must show progress on the terminal, not only in the log.
#     2026-11-11: `exec >>"$LOG"` ran before `exec 3>&1`, so fd 3 was the log
#     itself and a real run printed nothing - it looked like a no-op.
fd_line="$(grep -n 'exec 3>&1' "$REPO/scripts/tools/stabilize-once.sh" | head -1 | cut -d: -f1)"
log_line="$(grep -n 'exec >>"\$LOG"' "$REPO/scripts/tools/stabilize-once.sh" | head -1 | cut -d: -f1)"
check "stabilize-once captures the terminal before redirecting stdout" '[ -n "$fd_line" ] && [ -n "$log_line" ] && [ "$fd_line" -lt "$log_line" ]'
check "stabilize-once reports through out()" 'grep -q "^out()" "$REPO/scripts/tools/stabilize-once.sh"'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
