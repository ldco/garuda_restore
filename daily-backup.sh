#!/bin/bash
# ============================================================================
# Garuda KDE Linux - Daily Backup Script with Notifications
# ============================================================================
# This script runs the backup and shows KDE notifications on success/failure.
# Designed to be run via systemd timer or cron.
# Features: Start/Progress/Complete notifications, GUI sudo prompt
# ============================================================================

# Configuration
BACKUP_DEST="${BACKUP_DEST:-$HOME/Backups}"
KEEP_DAYS="${KEEP_DAYS:-7}"  # Keep backups for 7 days
LOG_FILE="$HOME/.local/share/garuda-backup/backup.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create directories
mkdir -p "$BACKUP_DEST"
mkdir -p "$(dirname "$LOG_FILE")"

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="garuda-backup-$TIMESTAMP"

# Set display for GUI compatibility (cron/systemd)
export DISPLAY="${DISPLAY:-:0}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

# Function to send notification (using notify-send - standard on Garuda)
# Each notification gets a unique ID based on its type so they don't replace each other
notify() {
    local title="$1"
    local message="$2"
    local icon="$3"
    local urgency="${4:-normal}"
    local replace_id="${5:-0}"

    if command -v notify-send &> /dev/null; then
        # Use different hint IDs to prevent notifications from replacing each other
        notify-send -u "$urgency" -i "$icon" -a "Garuda Backup" \
            -h "int:transient:1" \
            -h "string:x-canonical-private-synchronous:garuda-backup-$replace_id" \
            "$title" "$message" 2>/dev/null
    fi
}

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to run command with GUI sudo (kdesu)
gui_sudo() {
    if command -v kdesu &> /dev/null; then
        kdesu -t -c "$*"
    elif command -v pkexec &> /dev/null; then
        pkexec $@
    else
        # Fallback to terminal sudo
        sudo $@
    fi
}

# ============================================================================
# START BACKUP
# ============================================================================
log "=========================================="
log "Starting daily backup: $BACKUP_NAME"

# Notify: Backup Started (ID=1)
notify "🔄 Garuda Backup Started" "Preparing backup...\nYou will be asked for your password." "system-run" "normal" "start"

# Check if backup script exists
if [ ! -f "$SCRIPT_DIR/backup-settings.sh" ]; then
    log "ERROR: backup-settings.sh not found in $SCRIPT_DIR"
    notify "❌ Garuda Backup FAILED" "backup-settings.sh not found!" "dialog-error" "critical" "error"
    exit 1
fi

# Request sudo authentication FIRST using GUI dialog
log "Requesting sudo authentication..."

SUDO_SUCCESS=false

if [ -n "$DISPLAY" ]; then
    # Create a custom askpass script with proper message
    ASKPASS_SCRIPT=$(mktemp)
    cat > "$ASKPASS_SCRIPT" << 'EOF'
#!/bin/bash
# Custom askpass for Garuda Backup
if command -v kdialog &> /dev/null; then
    kdialog --password "Garuda Backup requires administrator privileges.\n\nEnter your password:" --title "🔐 Garuda Backup - Authentication"
elif command -v zenity &> /dev/null; then
    zenity --password --title="Garuda Backup - Authentication"
else
    # Fallback to ksshaskpass
    /usr/bin/ksshaskpass "Garuda Backup - Enter password:"
fi
EOF
    chmod +x "$ASKPASS_SCRIPT"
    export SUDO_ASKPASS="$ASKPASS_SCRIPT"

    # Use -A flag to use askpass program, this caches credentials properly
    if sudo -A -v 2>/dev/null; then
        SUDO_SUCCESS=true
        log "Sudo authenticated via GUI dialog"
    fi

    rm -f "$ASKPASS_SCRIPT"
fi

# Fallback to terminal sudo if GUI didn't work
if [ "$SUDO_SUCCESS" != "true" ]; then
    if sudo -v 2>/dev/null; then
        SUDO_SUCCESS=true
        log "Sudo authenticated via terminal"
    fi
fi

if [ "$SUDO_SUCCESS" != "true" ]; then
    log "ERROR: Sudo authentication failed or cancelled"
    notify "❌ Garuda Backup Cancelled" "Authentication failed or was cancelled." "dialog-error" "critical" "error"
    exit 1
fi

log "Sudo authentication successful"

# NOW show "In Progress" - after password was accepted!
sleep 1
notify "⏳ Garuda Backup In Progress" "Backing up packages, configs, KDE settings...\nThis may take several minutes." "document-save" "normal" "progress"

# Run the backup script
log "Running backup script..."
cd "$SCRIPT_DIR"

# Capture output and errors
if bash "$SCRIPT_DIR/backup-settings.sh" >> "$LOG_FILE" 2>&1; then
    # Backup succeeded

    # Find the created backup directory and archive
    BACKUP_DIR=$(ls -td "$HOME"/garuda-backup-* 2>/dev/null | head -1)
    ARCHIVE=$(ls -t "$HOME"/garuda-backup-*.tar.gz 2>/dev/null | head -1)

    if [ -n "$ARCHIVE" ] && [ -f "$ARCHIVE" ]; then
        # Remove "last" from previous backup filename
        PREV_LAST=$(ls "$BACKUP_DEST"/garuda-backup-*-last.tar.gz 2>/dev/null | head -1)
        if [ -n "$PREV_LAST" ] && [ -f "$PREV_LAST" ]; then
            NEW_NAME=$(echo "$PREV_LAST" | sed 's/-last\.tar\.gz$/.tar.gz/')
            mv "$PREV_LAST" "$NEW_NAME"
            log "Renamed previous: $(basename "$PREV_LAST") -> $(basename "$NEW_NAME")"
        fi

        # Move new archive and add "last" suffix
        ARCHIVE_BASENAME=$(basename "$ARCHIVE" .tar.gz)
        FINAL_ARCHIVE="$BACKUP_DEST/${ARCHIVE_BASENAME}-last.tar.gz"
        mv "$ARCHIVE" "$FINAL_ARCHIVE"

        # Remove the uncompressed backup directory to save space
        [ -d "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"

        # Get backup size
        BACKUP_SIZE=$(du -h "$FINAL_ARCHIVE" | cut -f1)

        log "SUCCESS: Backup saved to $FINAL_ARCHIVE ($BACKUP_SIZE)"
        notify "✅ Garuda Backup Complete" "Saved: $(basename "$FINAL_ARCHIVE")\nSize: $BACKUP_SIZE\nLocation: $BACKUP_DEST" "dialog-ok" "normal" "complete"
    else
        log "WARNING: Backup completed but archive not found"
        notify "⚠️ Garuda Backup Warning" "Backup ran but archive not found.\nCheck: $LOG_FILE" "dialog-warning" "normal" "warning"
    fi

    # Cleanup old backups - keep only 2: the "last" one and the previous one
    log "Cleaning up old backups (keeping only 2)..."

    # Get all backups sorted by date (newest first), skip the first 2
    BACKUPS_TO_DELETE=$(ls -t "$BACKUP_DEST"/garuda-backup-*.tar.gz 2>/dev/null | tail -n +3)

    if [ -n "$BACKUPS_TO_DELETE" ]; then
        echo "$BACKUPS_TO_DELETE" | while read -r old_backup; do
            log "Deleting old backup: $(basename "$old_backup")"
            rm -f "$old_backup"
        done
    fi

    # Count remaining backups
    BACKUP_COUNT=$(ls -1 "$BACKUP_DEST"/garuda-backup-*.tar.gz 2>/dev/null | wc -l)
    log "Cleanup complete. $BACKUP_COUNT backups remaining."

else
    # Backup failed
    log "ERROR: Backup script failed!"
    notify "❌ Garuda Backup FAILED" "Backup failed!\nCheck log: $LOG_FILE" "dialog-error" "critical" "error"
    exit 1
fi

log "Daily backup completed successfully"
log "=========================================="

