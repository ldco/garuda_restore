#!/usr/bin/env bash
# =============================================================================
# harness-run.sh - run a heavy AI/dev harness inside a memory-capped user scope
# =============================================================================
# Containment + graceful degradation (docs/OOM-WEZTERM.md,
# docs/ADR-harness-memory.md).
#
# L1 (per-scope isolation): the scope carries its own MemoryMax/MemorySwapMax,
#     so one instance can never consume the whole 18G harness.slice budget and
#     starve a second tab.
# L2 (graceful supervisor): a watchdog inside the scope measures *anon* memory
#     (memory.stat, not memory.current - the reclaimable file cache must not
#     trigger a restart) and sends SIGTERM at 85% of the per-scope cap. The
#     command then respawns as `nocowboy --continue`, so an overflow becomes a
#     clean restart with the session resumed instead of a kernel SIGKILL.
#
# Usage:  harness <command...>        e.g. harness nocowboy
#         harness -- <command...>     explicit separator
#
# The slice ceiling (MemoryMax=18G, MemorySwapMax=4G) is defined by
# oom-guard.sh in ~/.config/systemd/user/harness.slice and its drop-in; keep
# 2 x MemoryMax <= the slice ceiling when changing the split below.
#
# The scope is entered by re-invoking this same script with
# NOCOWBOY_HARNESS_SUPERVISOR=1: the supervisor therefore lives in a file, not
# in an argv string, so systemd never expands `$VAR` tokens inside it.
#
# oom_score_adj is raised to 900 from inside the scope before the command runs:
# systemd 262 rejects "OOMScoreAdjust=" as a transient *scope* property, and
# set-property cannot change it at runtime. Raising is always permitted
# unprivileged; every child inherits it.
# =============================================================================
set -Eeuo pipefail

SELF="$(readlink -f "${BASH_SOURCE[0]}")"

# --- tunables ---------------------------------------------------------------
# Keep in sync with scripts/tools/oom-guard.sh: slice = 18G memory / 4G swap,
# split evenly across two instances -> 9G / 2G per scope.
SCOPE_MEMORY_MAX="9G"
SCOPE_MEMORY_SWAP_MAX="2G"
# Graceful SIGTERM threshold: 85% of the 9G per-scope cap (~7.6 GiB) of anon
# memory. Above this the watchdog asks the harness to flush and exit, leaving
# ~1.4 GiB of headroom before the kernel's hard cap.
SOFT_LIMIT_BYTES="${HARNESS_SOFT_LIMIT_BYTES:-$((85 * 9 * 1024 * 1024 * 1024 / 100))}"
POLL_SECONDS=2
RESPAWN_DELAY=2
# ---------------------------------------------------------------------------

usage() {
    printf 'usage: harness <command...>\n\n'
    printf 'Runs <command> in its own memory-capped scope (harness.slice):\n'
    printf '  - per-scope MemoryMax=%s, MemorySwapMax=%s\n' "$SCOPE_MEMORY_MAX" "$SCOPE_MEMORY_SWAP_MAX"
    printf '  - oom_score_adj=900\n'
    printf '  - a watchdog sends SIGTERM at ~85%% of the cap, then a\n'
    printf '    `nocowboy --continue` restart resumes the session instead of\n'
    printf '    letting the kernel SIGKILL the TUI.\n'
}

# --- in-scope supervisor ----------------------------------------------------

# This process is the scope's main process; its cgroup holds the harness.
scope_dir() {
    local path
    path=$(awk -F: '$1 == "0" { print $3; exit }' /proc/self/cgroup 2>/dev/null) || true
    [ -n "${path:-}" ] || return 1
    printf '/sys/fs/cgroup%s' "$path"
}

anon_bytes() {
    local dir
    dir=$(scope_dir) || return 1
    awk '$1 == "anon" { print $2; exit }' "$dir/memory.stat" 2>/dev/null || return 1
}

# Watchdog: wait for the child pid, then poll anon memory until it crosses the
# soft limit. The fired marker is written before SIGTERM so the supervisor can
# tell a watchdog restart from a user quit, regardless of the exit code.
watchdog() {
    local pidfile=$1 fired=$2 pid=""
    while :; do
        if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
            pid=$(cat "$pidfile" 2>/dev/null || true)
            if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
                # Child is gone (or not started yet): stop once the wrapper has
                # written its pid, otherwise keep waiting.
                [ -s "$pidfile" ] && [ -n "${pid:-}" ] && return 0
                sleep 0.5
                continue
            fi
        fi
        local anon
        anon=$(anon_bytes) || true
        if [ -n "${anon:-}" ] && [ "$anon" -ge "$SOFT_LIMIT_BYTES" ]; then
            : > "$fired"
            echo "harness: memory watchdog: anon ${anon} >= ${SOFT_LIMIT_BYTES} bytes; SIGTERM pid ${pid}" >&2
            kill -TERM "$pid" 2>/dev/null || true
            return 0
        fi
        sleep "$POLL_SECONDS"
    done
}

supervisor() {
    if ! echo 900 > /proc/self/oom_score_adj 2>/dev/null; then
        echo "harness: warning: could not set oom_score_adj=900" >&2
    fi

    local respawn=false
    case "$(basename "$1")" in
        nocowboy) respawn=true ;;
    esac

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    while :; do
        local pidfile="$tmpdir/pid"
        local fired="$tmpdir/fired"
        : > "$pidfile"
        rm -f "$fired"
        watchdog "$pidfile" "$fired" &
        local wd=$!

        # Run the command in the foreground so it keeps the terminal's stdin (a
        # backgrounded TUI would get /dev/null stdin). The wrapper records its
        # pid, which survives `exec`, for the watchdog to target.
        local rc=0
        bash -c 'printf "%s" "$$" > "$1"; shift; exec "$@"' _ "$pidfile" "$@" || rc=$?

        kill "$wd" 2>/dev/null || true
        wait "$wd" 2>/dev/null || true

        if [ -e "$fired" ] && [ "$respawn" = true ]; then
            echo "harness: restarting after graceful shutdown: nocowboy --continue" >&2
            sleep "$RESPAWN_DELAY"
            set -- nocowboy --continue
            continue
        fi
        exit "$rc"
    done
}

# --- entry points -----------------------------------------------------------

if [ "${NOCOWBOY_HARNESS_SUPERVISOR:-}" = "1" ]; then
    supervisor "$@"
    exit $?
fi

if [ "$#" -eq 0 ]; then
    printf 'usage: harness <command...>\n' >&2
    printf '       harness -- <command...>\n' >&2
    exit 2
fi

case "$1" in
    -h|--help) usage; exit 0 ;;
    --) shift ;;
esac

if [ "$#" -eq 0 ]; then
    printf 'usage: harness <command...>\n' >&2
    printf '       harness -- <command...>\n' >&2
    exit 2
fi

exec systemd-run --user --scope --collect \
    --slice=harness.slice \
    -p MemoryAccounting=yes \
    -p "MemoryMax=${SCOPE_MEMORY_MAX}" \
    -p "MemorySwapMax=${SCOPE_MEMORY_SWAP_MAX}" \
    --setenv=NOCOWBOY_HARNESS_SUPERVISOR=1 \
    --setenv=HARNESS_SOFT_LIMIT_BYTES="${SOFT_LIMIT_BYTES}" \
    -- /bin/bash "$SELF" "$@"
