#!/usr/bin/env bash
# =============================================================================
# harness-run.sh - run a heavy AI/dev harness inside a memory-capped user scope
# =============================================================================
# Containment layer of the WezTerm OOM design (docs/OOM-WEZTERM.md).
# The scope lives in harness.slice, so a runaway harness is OOM-killed inside
# its own cgroup and can never take the terminal or the compositor down.
#
# Usage:  harness <command...>        e.g. harness nocowboy
#         harness -- <command...>     explicit separator
#
# The ceiling (MemoryMax=18G, MemorySwapMax=4G) is defined by oom-guard.sh in
# ~/.config/systemd/user/harness.slice and its drop-in.
#
# oom_score_adj is raised to 900 from inside the scope before exec: systemd 262
# rejects "OOMScoreAdjust=" as a transient *scope* property ("Unknown assignment:
# OOMScoreAdjust=900"), and set-property cannot change it at runtime either.
# Raising is always permitted for an unprivileged process; children inherit it.
# =============================================================================
set -Eeuo pipefail

if [ "$#" -eq 0 ]; then
    printf 'usage: harness <command...>\n' >&2
    printf '       harness -- <command...>\n' >&2
    exit 2
fi

case "$1" in
    -h|--help)
        printf 'usage: harness <command...>\n\n'
        printf 'Runs <command> in harness.slice (memory capped,\n'
        printf 'oom_score_adj=900) so a runaway process is OOM-killed inside its\n'
        printf 'own cgroup instead of taking WezTerm down.\n'
        exit 0
        ;;
    --)
        shift
        ;;
esac

if [ "$#" -eq 0 ]; then
    printf 'usage: harness <command...>\n' >&2
    exit 2
fi

exec systemd-run --user --scope --collect \
    --slice=harness.slice \
    -p MemoryAccounting=yes \
    -- /bin/bash -c 'if ! echo 900 > /proc/self/oom_score_adj 2>/dev/null; then
        echo "harness: warning: could not set oom_score_adj=900" >&2
    fi
    exec "$@"' harness "$@"
