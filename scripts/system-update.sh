#!/bin/bash

# ============================================
# SYSTEM UPDATE & MAINTENANCE
# Updates, cleans, optimizes
# ============================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}      SYSTEM UPDATE & MAINTENANCE${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""

# ============================================
# PRE-UPDATE INFO
# ============================================
echo -e "${CYAN}Current State:${NC}"
echo "─────────────────────"
echo "Installed packages: $(pacman -Q | wc -l)"
echo "Orphan packages: $(pacman -Qdt 2>/dev/null | wc -l)"
echo "Package cache: $(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)"
echo "AUR packages: $(pacman -Qm 2>/dev/null | wc -l)"
echo ""

# ============================================
# 1. SYSTEM UPDATE
# ============================================
echo -e "${BOLD}[1/6] System Update${NC}"
echo "─────────────────────"

read -p "Update system packages? [Y/n]: " UPDATE
if [[ ! "$UPDATE" =~ ^[Nn]$ ]]; then
    # Use garuda-update (handles mirrors, snapshots, keyrings)
    # Falls back to paru/yay/pacman for non-Garuda systems
    if command -v garuda-update &>/dev/null; then
        garuda-update
    elif command -v paru &>/dev/null; then
        paru -Syu
    elif command -v yay &>/dev/null; then
        yay -Syu
    else
        sudo pacman -Syu
    fi
    echo -e "${GREEN}✓ System updated${NC}"
else
    echo "Skipped"
fi
echo ""

# ============================================
# 2. CLEAN PACKAGE CACHE
# ============================================
echo -e "${BOLD}[2/6] Clean Package Cache${NC}"
echo "─────────────────────"

CACHE_SIZE=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)
CACHE_MB=$(du -sm /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)

echo "Current cache size: $CACHE_SIZE"

if [ -n "$CACHE_MB" ] && [ "$CACHE_MB" -gt 5000 ]; then
    # Show what would be removed
    SAVINGS=$(paccache -dk2 2>/dev/null | tail -1 | grep -oP '\d+\.\d+ \w+' || echo "unknown")
    echo "Can free: $SAVINGS (keeping 2 versions)"

    read -p "Clean package cache? [Y/n]: " CLEAN_CACHE
    if [[ ! "$CLEAN_CACHE" =~ ^[Nn]$ ]]; then
        sudo paccache -rk2
        echo -e "${GREEN}✓ Cache cleaned${NC}"
    else
        echo "Skipped"
    fi
else
    echo -e "${GREEN}Cache is reasonable size, skipping${NC}"
fi
echo ""

# ============================================
# 3. REMOVE ORPHAN PACKAGES
# ============================================
echo -e "${BOLD}[3/6] Remove Orphan Packages${NC}"
echo "─────────────────────"

ORPHANS=$(pacman -Qdt 2>/dev/null)
ORPHAN_COUNT=$(echo "$ORPHANS" | grep -c . 2>/dev/null || echo 0)

if [ "$ORPHAN_COUNT" -gt 0 ]; then
    echo "Found $ORPHAN_COUNT orphan packages:"
    echo "$ORPHANS" | head -10
    [ "$ORPHAN_COUNT" -gt 10 ] && echo "... and $((ORPHAN_COUNT - 10)) more"
    echo ""

    read -p "Remove orphan packages? [Y/n]: " REMOVE_ORPHANS
    if [[ ! "$REMOVE_ORPHANS" =~ ^[Nn]$ ]]; then
        sudo pacman -Rns $(pacman -Qdtq) --noconfirm
        echo -e "${GREEN}✓ Orphans removed${NC}"
    else
        echo "Skipped"
    fi
else
    echo -e "${GREEN}No orphan packages found${NC}"
fi
echo ""

# ============================================
# 4. CLEAN USER CACHE
# ============================================
echo -e "${BOLD}[4/6] Clean User Cache${NC}"
echo "─────────────────────"

USER_CACHE=$(du -sh ~/.cache 2>/dev/null | cut -f1)
echo "User cache size: $USER_CACHE"

# Check for large cache directories
LARGE_CACHES=""
for dir in ~/.cache/thumbnails ~/.cache/mozilla ~/.cache/chromium ~/.cache/google-chrome ~/.cache/BraveSoftware ~/.cache/pip ~/.cache/yarn ~/.cache/npm; do
    if [ -d "$dir" ]; then
        SIZE=$(du -sm "$dir" 2>/dev/null | cut -f1)
        if [ -n "$SIZE" ] && [ "$SIZE" -gt 500 ]; then
            LARGE_CACHES="$LARGE_CACHES\n  $(du -sh "$dir" 2>/dev/null)"
        fi
    fi
done

if [ -n "$LARGE_CACHES" ]; then
    echo -e "Large cache directories:$LARGE_CACHES"
    echo ""
    read -p "Clean thumbnails cache? [y/N]: " CLEAN_THUMBS
    if [[ "$CLEAN_THUMBS" =~ ^[Yy]$ ]]; then
        rm -rf ~/.cache/thumbnails/*
        echo -e "${GREEN}✓ Thumbnails cleaned${NC}"
    fi
else
    echo -e "${GREEN}User cache is reasonable${NC}"
fi
echo ""

# ============================================
# 5. CLEAN JOURNAL LOGS
# ============================================
echo -e "${BOLD}[5/6] Clean Journal Logs${NC}"
echo "─────────────────────"

JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' || echo "unknown")
echo "Journal size: $JOURNAL_SIZE"

read -p "Vacuum journal to 100M? [y/N]: " CLEAN_JOURNAL
if [[ "$CLEAN_JOURNAL" =~ ^[Yy]$ ]]; then
    sudo journalctl --vacuum-size=100M
    echo -e "${GREEN}✓ Journal cleaned${NC}"
else
    echo "Skipped"
fi
echo ""

# ============================================
# 6. ADDITIONAL MAINTENANCE
# ============================================
echo -e "${BOLD}[6/6] Additional Maintenance${NC}"
echo "─────────────────────"

# Failed systemd services
FAILED=$(systemctl --failed --no-pager 2>/dev/null | grep -c "failed")
if [ "$FAILED" -gt 0 ]; then
    echo -e "${YELLOW}Found $FAILED failed services${NC}"
    systemctl --failed --no-pager 2>/dev/null | grep "failed"
    echo ""
    read -p "Reset failed services? [y/N]: " RESET_FAILED
    if [[ "$RESET_FAILED" =~ ^[Yy]$ ]]; then
        sudo systemctl reset-failed
        echo -e "${GREEN}✓ Failed services reset${NC}"
    fi
else
    echo -e "${GREEN}No failed services${NC}"
fi

# Pacman database optimization
read -p "Optimize pacman database? [y/N]: " OPTIMIZE_DB
if [[ "$OPTIMIZE_DB" =~ ^[Yy]$ ]]; then
    sudo pacman-db-upgrade 2>/dev/null || true
    echo -e "${GREEN}✓ Database optimized${NC}"
fi

# Update font cache
read -p "Refresh font cache? [y/N]: " REFRESH_FONTS
if [[ "$REFRESH_FONTS" =~ ^[Yy]$ ]]; then
    fc-cache -fv > /dev/null 2>&1
    echo -e "${GREEN}✓ Font cache refreshed${NC}"
fi

# Update desktop database
read -p "Update desktop database? [y/N]: " UPDATE_DESKTOP
if [[ "$UPDATE_DESKTOP" =~ ^[Yy]$ ]]; then
    update-desktop-database ~/.local/share/applications 2>/dev/null || true
    echo -e "${GREEN}✓ Desktop database updated${NC}"
fi

echo ""

# ============================================
# SUMMARY
# ============================================
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo -e "${BOLD}      COMPLETE${NC}"
echo -e "${BOLD}════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Post-update state:${NC}"
echo "─────────────────────"
echo "Installed packages: $(pacman -Q | wc -l)"
echo "Orphan packages: $(pacman -Qdt 2>/dev/null | wc -l)"
echo "Package cache: $(du -sh /var/cache/pacman/pkg/ 2>/dev/null | cut -f1)"
echo ""

# Check if reboot needed
if [ -f /var/run/reboot-required ] || [ -n "$(pacman -Qu linux 2>/dev/null)" ]; then
    echo -e "${YELLOW}${BOLD}Reboot recommended (kernel updated)${NC}"
else
    echo -e "${GREEN}${BOLD}✓ System is up to date${NC}"
fi
echo ""
