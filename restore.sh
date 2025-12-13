#!/bin/bash
# ============================================================================
# Garuda KDE Linux - ONE-CLICK RESTORE
# ============================================================================
# This script automatically:
#   1. Finds the backup archive (or asks you to select one)
#   2. Extracts it
#   3. Runs the restore
#   4. Cleans up
#
# Just run: ./restore.sh
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║         Garuda KDE Linux - ONE-CLICK RESTORE                         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

# Find backup archives
BACKUP_ARCHIVES=()

# Look in current directory
for f in "$SCRIPT_DIR"/garuda-backup-*.tar.gz; do
    [ -f "$f" ] && BACKUP_ARCHIVES+=("$f")
done

# Look in parent directory
for f in "$SCRIPT_DIR"/../garuda-backup-*.tar.gz; do
    [ -f "$f" ] && BACKUP_ARCHIVES+=("$f")
done

# Look in home directory
for f in "$HOME"/garuda-backup-*.tar.gz; do
    [ -f "$f" ] && BACKUP_ARCHIVES+=("$f")
done

# Check if we found any
if [ ${#BACKUP_ARCHIVES[@]} -eq 0 ]; then
    echo "No backup archives found!"
    echo ""
    echo "Please provide the path to your backup archive:"
    read -p "Path: " ARCHIVE_PATH
    
    if [ ! -f "$ARCHIVE_PATH" ]; then
        echo "ERROR: File not found: $ARCHIVE_PATH"
        exit 1
    fi
else
    echo "Found backup archives:"
    echo ""
    
    # Sort by date (newest first) and show
    i=1
    for archive in "${BACKUP_ARCHIVES[@]}"; do
        size=$(du -h "$archive" | cut -f1)
        name=$(basename "$archive")
        if [[ "$name" == *"-last"* ]]; then
            echo "  $i) $name ($size) ← LATEST"
        else
            echo "  $i) $name ($size)"
        fi
        ((i++))
    done
    
    echo ""
    
    if [ ${#BACKUP_ARCHIVES[@]} -eq 1 ]; then
        ARCHIVE_PATH="${BACKUP_ARCHIVES[0]}"
        echo "Using: $(basename "$ARCHIVE_PATH")"
    else
        read -p "Select archive number [1]: " choice
        choice=${choice:-1}
        ARCHIVE_PATH="${BACKUP_ARCHIVES[$((choice-1))]}"
    fi
fi

echo ""
echo "Selected: $(basename "$ARCHIVE_PATH")"
echo "Size: $(du -h "$ARCHIVE_PATH" | cut -f1)"
echo ""
read -p "Press Enter to start restore (Ctrl+C to cancel)..."

# Create temp directory for extraction
TEMP_DIR=$(mktemp -d)
echo ""
echo "Extracting backup..."

tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR"

# Find the extracted directory
BACKUP_DIR=$(ls -d "$TEMP_DIR"/garuda-backup-* 2>/dev/null | head -1)

if [ ! -d "$BACKUP_DIR" ]; then
    echo "ERROR: Could not find extracted backup directory"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Extracted to: $BACKUP_DIR"
echo ""

# Check for restore script
if [ -f "$BACKUP_DIR/restore-settings.sh" ]; then
    RESTORE_SCRIPT="$BACKUP_DIR/restore-settings.sh"
elif [ -f "$SCRIPT_DIR/restore-settings.sh" ]; then
    RESTORE_SCRIPT="$SCRIPT_DIR/restore-settings.sh"
else
    echo "ERROR: restore-settings.sh not found!"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Make executable and run
chmod +x "$RESTORE_SCRIPT"

echo "Running restore..."
echo ""

# Run the restore script with the backup directory
cd "$BACKUP_DIR"
bash "$RESTORE_SCRIPT"

# Cleanup
echo ""
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║                     RESTORE COMPLETE!                                 ║"
echo "║                                                                       ║"
echo "║   Please reboot now:  sudo reboot                                    ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

