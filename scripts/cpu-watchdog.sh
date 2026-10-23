#!/bin/bash
# ============================================================================
# CPU WATCHDOG - Alerts/kills runaway processes (with whitelist)
# ============================================================================
# Run via systemd timer every 15 minutes
# Whitelist based on ACTUALLY INSTALLED apps on this system
# ============================================================================

CPU_THRESHOLD=80        # Alert if process uses more than this %
TIME_THRESHOLD=3600     # Alert if running more than this (seconds = 1 hour)
# Must match the deployment path used by cpu-watchdog.service and run-hh-agent.sh
LOG_FILE="$HOME/.local/share/garuda-backup-scripts/watchdog.log"

# ---------------------------------------------------------------------------
# THROTTLE
# ---------------------------------------------------------------------------
# This script has two callers: cpu-watchdog.timer (every 15 min, correct) and
# run-hh-agent.sh (every 5 s, far too often). Without a guard the 5s caller
# turns this into ~17k full `ps aux` scans per day. Perform the real scan at
# most once per THROTTLE_SECONDS, whoever calls it.
# ---------------------------------------------------------------------------
THROTTLE_SECONDS=600
THROTTLE_STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/garuda-cpu-watchdog.stamp"
if [ -f "$THROTTLE_STAMP" ]; then
    _last=$(stat -c %Y "$THROTTLE_STAMP" 2>/dev/null || echo 0)
    _now=$(date +%s)
    if [ $((_now - _last)) -lt "$THROTTLE_SECONDS" ]; then
        exit 0
    fi
fi
mkdir -p "$(dirname "$THROTTLE_STAMP")"
touch "$THROTTLE_STAMP"

# ============================================================================
# WHITELIST - Based on YOUR installed apps
# ============================================================================
WHITELIST=(
    # Gaming (installed: steam)
    "steam"
    "gamescope"
    "wine"
    "proton"
    ".exe"              # Windows games via Wine/Proton

    # Video/Audio Production (installed: davinci-resolve, kdenlive, audacity, handbrake, ffmpeg)
    "resolve"           # DaVinci Resolve
    "kdenlive"
    "audacity"
    "ffmpeg"
    "handbrake"

    # 3D / Graphics (installed: blender, krita, gimp, inkscape)
    "blender"
    "krita"
    "gimp"
    "inkscape"

    # AI / ML (ComfyUI, Fooocus in ~/*)
    "python"            # ComfyUI, Fooocus, ML training
    "comfyui"
    "fooocus"
    "torch"

    # Development (installed: gcc, docker, node via nvm)
    "cargo"
    "rustc"
    "gcc"
    "g++"
    "make"
    "node"
    "docker"

    # Browsers (installed: brave-bin, google-chrome)
    "brave"
    "chrome"

    # IDE (installed: visual-studio-code-bin)
    "code"
    "electron"          # VS Code runs on electron

    # Communication (installed: telegram, discord, zoom)
    "telegram"
    "discord"
    "zoom"

    # Media (installed: vlc, mpv, spotify)
    "vlc"
    "mpv"

    # NoCowboy agent stack — normal workload on this machine, never a runaway
    "nocowboy"
    "bun"
    "rg"                # ripgrep, spawned heavily by agent test runs
    "esbuild"
    "tsc"
    "pyright"

    # System
    "pacman"
    "paru"
    "makepkg"
    "gzip"
    "tar"
    "rsync"
)

# Extended time threshold for whitelisted processes (4 hours instead of 1)
WHITELIST_TIME_THRESHOLD=14400

mkdir -p "$(dirname "$LOG_FILE")"

# Function to check if process is whitelisted
is_whitelisted() {
    local cmd="$1"
    for pattern in "${WHITELIST[@]}"; do
        if [[ "${cmd,,}" == *"${pattern,,}"* ]]; then
            return 0  # Whitelisted
        fi
    done
    return 1  # Not whitelisted
}

# Get processes using high CPU
ps aux --sort=-%cpu | awk -v thresh="$CPU_THRESHOLD" '
NR>1 && $3 > thresh {
    print $2, $3, $11
}' | while read PID CPU CMD; do
    # Get process start time in seconds
    START_TIME=$(ps -o etimes= -p "$PID" 2>/dev/null | tr -d ' ')
    [ -z "$START_TIME" ] && continue

    # Check if whitelisted
    if is_whitelisted "$CMD"; then
        # Use longer threshold for whitelisted apps
        if [ "$START_TIME" -gt "$WHITELIST_TIME_THRESHOLD" ]; then
            echo "[$(date)] INFO: Whitelisted $CMD (PID $PID) using ${CPU}% CPU for $(($START_TIME/3600))h - monitoring" >> "$LOG_FILE"
        fi
        continue
    fi

    # Non-whitelisted process using high CPU for too long
    if [ "$START_TIME" -gt "$TIME_THRESHOLD" ]; then
        HOURS=$(($START_TIME/3600))
        MINS=$((($START_TIME%3600)/60))

        echo "[$(date)] WARNING: $CMD (PID $PID) using ${CPU}% CPU for ${HOURS}h ${MINS}m" >> "$LOG_FILE"

        # Send desktop notification
        notify-send -u critical "CPU Watchdog" \
            "Suspicious process: $CMD\nUsing ${CPU}% CPU for ${HOURS}h ${MINS}m\n\nKill with: kill $PID"

        # Auto-kill after 2 hours (uncomment to enable)
        # if [ "$START_TIME" -gt 7200 ]; then
        #     echo "[$(date)] AUTO-KILL: $CMD (PID $PID)" >> "$LOG_FILE"
        #     kill "$PID"
        # fi
    fi
done
