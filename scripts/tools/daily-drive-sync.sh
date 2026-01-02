#!/bin/bash
# ============================================================================
# Daily Drive Sync - Syncs working drive to backup external drive
# ============================================================================
# Features: Start/Progress/Complete notifications, GUI sudo prompt, rsync
# ============================================================================

# ============================================================================
# CONFIGURATION - SAFETY: SOURCE is LAPTOP, DEST is EXTERNAL BACKUP
# ============================================================================
# SOURCE = Your working laptop drive (the one you work on daily)
SOURCE_DRIVE="/run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb"
SOURCE_LABEL="LAPTOP WORKING DRIVE"
SOURCE_IDENTIFIER="3734114f-7123-41f5-8f63-7f43c94879eb"

# DEST = External backup drive ROOT (where backups go - direct copy, no subfolder!)
DEST_DRIVE="/run/media/ldco/LDCO_BCP_2TB"
DEST_LABEL="EXTERNAL BACKUP (LDCO_BCP_2TB) - ROOT"
DEST_IDENTIFIER="LDCO_BCP"  # Safety check: dest path MUST contain this

# Sync directly to root of external drive (no subfolder!)
DEST_PATH="$DEST_DRIVE"
LOG_FILE="$HOME/.local/share/drive-sync/sync.log"
LOCK_FILE="/tmp/drive-sync.lock"

# LUKS encrypted backup drive info
BACKUP_PARTITION="/dev/disk/by-uuid/5b0fa7b1-4000-40e4-b49d-dc0b5e72d449"
BACKUP_LUKS_NAME="luks-5b0fa7b1-4000-40e4-b49d-dc0b5e72d449"

# Create directories
mkdir -p "$(dirname "$LOG_FILE")"

# Set display for GUI compatibility (cron/systemd)
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# Function to send notification
notify() {
    local title="$1"
    local message="$2"
    local icon="$3"
    local urgency="${4:-normal}"
    local replace_id="${5:-0}"

    if command -v notify-send &> /dev/null; then
        notify-send -u "$urgency" -i "$icon" -a "Drive Sync" \
            -h "int:transient:1" \
            -h "string:x-canonical-private-synchronous:drive-sync-$replace_id" \
            "$title" "$message" 2>/dev/null
    fi
}

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Prevent multiple instances
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        log "ERROR: Sync already running (PID: $PID)"
        notify "⚠️ Drive Sync Skipped" "Another sync is already running" "dialog-warning" "normal" "error"
        exit 1
    fi
fi
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# ============================================================================
# START SYNC
# ============================================================================
log "=========================================="
log "Starting daily drive sync"

# ============================================================================
# CRITICAL SAFETY CHECK - VERIFY DIRECTION IS CORRECT
# ============================================================================

# Safety Check 1: Verify DEST path contains the backup identifier
if [[ "$DEST_DRIVE" != *"$DEST_IDENTIFIER"* ]]; then
    log "CRITICAL ERROR: Destination path doesn't contain '$DEST_IDENTIFIER' - ABORTING for safety!"
    kdialog --error "🚨 CRITICAL SAFETY ERROR!\n\nDestination drive doesn't look like the backup drive!\n\nExpected: Path containing '$DEST_IDENTIFIER'\nGot: $DEST_DRIVE\n\nSync ABORTED to protect your data." 2>/dev/null
    exit 1
fi

# Safety Check 2: Verify SOURCE is not the backup drive
if [[ "$SOURCE_DRIVE" == *"$DEST_IDENTIFIER"* ]]; then
    log "CRITICAL ERROR: Source path contains '$DEST_IDENTIFIER' - This looks like the backup drive! ABORTING!"
    kdialog --error "🚨 CRITICAL SAFETY ERROR!\n\nSource drive looks like the BACKUP drive!\n\nThis would OVERWRITE your laptop with backup data!\n\nSync ABORTED to protect your data." 2>/dev/null
    exit 1
fi

log "Safety check PASSED: Source=$SOURCE_DRIVE, Dest=$DEST_DRIVE"

# Check if source drive is mounted
if [ ! -d "$SOURCE_DRIVE" ]; then
    log "ERROR: Source drive not mounted: $SOURCE_DRIVE"
    notify "❌ Drive Sync FAILED" "Source drive not mounted!" "dialog-error" "critical" "error"
    exit 1
fi

# ============================================================================
# CHECK BACKUP DRIVE IS MOUNTED (mount-triggered mode - no auto-unlock)
# ============================================================================
# This script is triggered by systemd when the backup drive is mounted.
# The user manually unlocks the LUKS drive via KDE, then this runs automatically.

if [ ! -d "$DEST_DRIVE" ] || ! mountpoint -q "$DEST_DRIVE" 2>/dev/null; then
    log "ERROR: Backup drive not mounted at $DEST_DRIVE"
    log "Please manually unlock and mount the backup drive first."
    notify "❌ Drive Sync FAILED" "Backup drive not mounted!\nUnlock LDCO_BCP_2TB first, sync will start automatically." "dialog-error" "critical" "error"
    exit 1
fi

log "Backup drive detected at $DEST_DRIVE"

# Check if destination is writable
if ! touch "$DEST_DRIVE/.sync_test" 2>/dev/null; then
    log "ERROR: Backup drive is not writable (read-only?)"
    notify "❌ Drive Sync FAILED" "Backup drive is read-only!\nMay need fsck repair." "dialog-error" "critical" "error"
    exit 1
fi
rm -f "$DEST_DRIVE/.sync_test"

# Create destination directory
mkdir -p "$DEST_PATH"

# ============================================================================
# SYNC MODE - SILENT SAFE BACKUP (no prompts)
# ============================================================================
USE_DELETE=false  # Always SAFE mode - keep old files on destination

log "Silent backup mode: SAFE BACKUP (keeps old files) + ALL FILES"
log "Source: $SOURCE_DRIVE"
log "Destination: $DEST_PATH"

# Notify: Sync Started
notify "🔄 Drive Sync Started" "Syncing to backup drive...\nMode: Safe Backup (keeps old files)\nThis may take a while." "sync-synchronizing" "normal" "start"

# Run rsync with progress
log "Running rsync..."
RSYNC_START=$(date +%s)

# Build rsync command based on user choice
RSYNC_OPTS="-aHAXv --progress --exclude=.Trash-* --exclude=lost+found --exclude=3734114f-7123-41f5-8f63-7f43c94879eb"

# Create a named pipe for progress
PROGRESS_PIPE="/tmp/drive-sync-progress-$$"
mkfifo "$PROGRESS_PIPE" 2>/dev/null || true

# Function to parse rsync progress and update GUI
show_gui_progress() {
    local pipe="$1"
    local src="$2"
    local dst="$3"
    local mode="$4"
    local dbus_ref=""
    local last_percent="0"
    local last_speed=""
    local dialog_created=false

    # Function to create/recreate the progress dialog
    create_dialog() {
        dbus_ref=$(kdialog --title "🔄 Drive Sync Progress" --progressbar "Starting sync..." 100 2>/dev/null)
        if [ -n "$dbus_ref" ]; then
            qdbus $dbus_ref Set "" value "$last_percent" 2>/dev/null
            dialog_created=true
            return 0
        fi
        return 1
    }

    # Function to check if dialog is still alive
    dialog_alive() {
        if [ -n "$dbus_ref" ]; then
            qdbus $dbus_ref 2>/dev/null | grep -q "org.kde.kdialog" && return 0
        fi
        return 1
    }

    # DON'T create dialog yet - wait for first rsync output (after password is entered)

    while IFS= read -r line; do
        # Parse rsync --info=progress2 output: "1,234,567  45%  100.00MB/s  0:01:23"
        if [[ "$line" =~ ([0-9]+)% ]]; then
            last_percent="${BASH_REMATCH[1]}"
            # Extract speed if available
            if [[ "$line" =~ ([0-9]+[,.][0-9]+[MKG]B/s) ]]; then
                last_speed="${BASH_REMATCH[1]}"
                status_line="⏳ Progress: ${last_percent}% @ ${last_speed}"
            else
                status_line="⏳ Progress: ${last_percent}%"
            fi

            # Create dialog on FIRST progress output (after password entered)
            if [ "$dialog_created" = false ]; then
                create_dialog
            fi

            # Check if dialog died and recreate it
            if ! dialog_alive; then
                log "Progress dialog died, recreating..."
                create_dialog
            fi

            # Update the dialog
            if [ -n "$dbus_ref" ]; then
                qdbus $dbus_ref setLabelText "$status_line\n\n📂 FROM: $src\n📁 TO: $dst\n🔧 Mode: $mode" 2>/dev/null
                qdbus $dbus_ref Set "" value "$last_percent" 2>/dev/null
            fi
        fi
    done < "$pipe"

    # Close dialog when done
    if [ -n "$dbus_ref" ]; then
        qdbus $dbus_ref close 2>/dev/null
    fi
}

# Determine mode name for display
MODE_NAME="SAFE BACKUP (keeps all files)"

# Use sudo with GUI askpass for password prompt
export SUDO_ASKPASS="/usr/bin/ksshaskpass"
export SUDO_PROMPT="🔐 Drive Sync needs your password to backup all files:"

log "Running rsync with elevated privileges (SAFE mode)"

# Authenticate FIRST with sudo -A (shows GUI password prompt)
if ! sudo -A -v 2>/dev/null; then
    log "ERROR: Authentication failed or cancelled"
    notify "❌ Sync Cancelled" "Password authentication failed or was cancelled" "dialog-error" "critical" "error"
    rm -f "$PROGRESS_PIPE"
    exit 1
fi

log "Authentication successful, starting sync..."

# NOW start the progress window (after password entered)
show_gui_progress "$PROGRESS_PIPE" "$SOURCE_DRIVE" "$DEST_PATH" "$MODE_NAME" &
GUI_PID=$!

# Run rsync with sudo (credentials are cached)
sudo rsync $RSYNC_OPTS "$SOURCE_DRIVE/" "$DEST_PATH/" 2>&1 | tee -a "$LOG_FILE" | tee "$PROGRESS_PIPE"

# Cleanup
rm -f "$PROGRESS_PIPE"
wait $GUI_PID 2>/dev/null

RSYNC_EXIT=${PIPESTATUS[0]}
RSYNC_END=$(date +%s)
RSYNC_DURATION=$((RSYNC_END - RSYNC_START))
RSYNC_MINUTES=$((RSYNC_DURATION / 60))
RSYNC_SECONDS=$((RSYNC_DURATION % 60))

if [ $RSYNC_EXIT -eq 0 ]; then
    # Get synced size
    DEST_SIZE=$(du -sh "$DEST_PATH" 2>/dev/null | cut -f1)
    
    log "SUCCESS: Sync completed in ${RSYNC_MINUTES}m ${RSYNC_SECONDS}s"
    log "Destination size: $DEST_SIZE"
    notify "✅ Drive Sync Complete" "Synced: $DEST_SIZE\nDuration: ${RSYNC_MINUTES}m ${RSYNC_SECONDS}s\nTo: LDCO_BCP_2TB" "dialog-ok" "normal" "complete"
else
    log "ERROR: rsync failed with exit code $RSYNC_EXIT"
    notify "❌ Drive Sync FAILED" "rsync error code: $RSYNC_EXIT\nCheck: $LOG_FILE" "dialog-error" "critical" "error"
    exit 1
fi

log "Daily sync completed successfully"
log "=========================================="

