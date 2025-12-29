#!/usr/bin/env bash
# Setup zoxide database with main disk folders
# Run once to seed zoxide with your project directories

set -e

DISK="/run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb"

# Check if zoxide is installed
if ! command -v zoxide &>/dev/null; then
    echo "Error: zoxide not installed. Run: paru -S zoxide"
    exit 1
fi

# Check if disk is mounted
if [ ! -d "$DISK" ]; then
    echo "Error: Disk not mounted at $DISK"
    exit 1
fi

echo "Seeding zoxide database with folders from: $DISK"
echo "This will add directories to your zoxide database..."
echo ""

# Exclude patterns
EXCLUDE_DIRS=(
    "node_modules"
    ".git"
    "__pycache__"
    "venv"
    ".venv"
    ".cache"
    ".Trash*"
    "Trash"
    ".pnpm-store"
    ".docker"
    ".ssh"
    "deprecated"
    "Deprecated"
    "_archive*"
    ".next"
    "dist"
    "build"
    ".nuxt"
    "target"
    ".cargo"
    "DWNLDS_torr"
)

# Build find exclusion pattern
PRUNE_ARGS=""
for dir in "${EXCLUDE_DIRS[@]}"; do
    PRUNE_ARGS="$PRUNE_ARGS -name $dir -o"
done
# Remove trailing -o
PRUNE_ARGS="${PRUNE_ARGS% -o}"

# Find all directories up to 4 levels deep, excluding noise
count=0
while IFS= read -r dir; do
    if [ -d "$dir" ]; then
        # Add to zoxide (simulates visiting the directory)
        zoxide add "$dir" 2>/dev/null && ((count++)) || true
    fi
done < <(find "$DISK" -maxdepth 4 -type d \( $PRUNE_ARGS \) -prune -o -type d -print 2>/dev/null)

echo ""
echo "Added $count directories to zoxide database"
echo ""
echo "Now you can use:"
echo "  z comfy     -> /run/media/.../ComfyUI"
echo "  z current   -> /run/media/.../CURRENT_WORKING_DEV"
echo "  z garuda    -> /run/media/.../LinuxDCO/garuda-restore"
echo "  z new       -> /run/media/.../NEW_ORDER"
echo ""
echo "Tip: The more you use 'z' to navigate, the smarter it gets!"
