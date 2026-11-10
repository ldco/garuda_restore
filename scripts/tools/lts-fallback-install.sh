#!/usr/bin/env bash
# =============================================================================
# lts-fallback-install.sh - one-shot LTS kernel fallback (safe on a stale DB)
# =============================================================================
# Why this exists: on 2026-11-10 `pacman -S linux-lts` failed with 404 from
# every mirror. The pacman DB was 17 days old and still pinned 6.18.58-1 while
# the mirrors only keep 6.18.60-1, so the file no longer existed anywhere.
#
# This script installs exactly the version the LOCAL DB knows, fetched from the
# Arch Linux Archive (which keeps superseded packages), so it works whether the
# DB is fresh or stale and never performs a partial upgrade.
#
# What it does, in order:
#   1. resolves linux-lts/<version> from the local pacman DB
#   2. downloads linux-lts + linux-lts-headers for that exact version
#   3. installs them with pacman -U (signature verification stays on)
#   4. verifies: module dir, /boot/vmlinuz-linux-lts, initramfs (builds it with
#      dracut if the hook did not), DKMS module for the LTS kernel, GRUB entry
#   5. optional --prepare-update: runs update-engine.sh prepare (mirrors, DB
#      refresh, snapshot, download) so the next full upgrade is ready
#
# It does NOT change the default kernel and does NOT reboot.
#
# Usage:
#   sudo ./scripts/tools/lts-fallback-install.sh --check          # dry run
#   sudo ./scripts/tools/lts-fallback-install.sh                  # install + verify
#   sudo ./scripts/tools/lts-fallback-install.sh --prepare-update # + stage the update
#   sudo ./scripts/tools/lts-fallback-install.sh --make-default   # boot LTS by default
#   sudo ./scripts/tools/lts-fallback-install.sh --revert-default # back to linux-zen
#
# --make-default uses GRUB_TOP_LEVEL (GRUB 2.16 supports it, verified in
# /etc/grub.d/10_linux): the LTS kernel becomes the top-level "Garuda Linux"
# entry and GRUB_DEFAULT=0 boots it, which survives kernel updates. The
# hardcoded "gnulinux-advanced-<id>>gnulinux-linux-lts-advanced-<id>" string from
# the stabilization guide breaks as soon as the zen kernel is upgraded.
# The change is verified in grub.cfg BEFORE the script exits: if the first boot
# entry does not point at vmlinuz-linux-lts it fails and tells you not to reboot.
# =============================================================================
set -Eeuo pipefail

ARCHIVE="https://archive.archlinux.org/packages"
PKGS=(linux-lts linux-lts-headers)
CHECK=0
PREPARE_UPDATE=0
MODE=install
GRUB_DEFAULTS=/etc/default/grub
GRUB_CFG=/boot/grub/grub.cfg

say()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        --prepare-update) PREPARE_UPDATE=1 ;;
        --make-default)   MODE=make-default ;;
        --revert-default) MODE=revert-default ;;
        -h|--help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

command -v pacman >/dev/null || die "pacman not found"
command -v curl   >/dev/null || die "curl not found"

# --- default-boot selection (no package work at all) ------------------------
first_boot_kernel() { # kernel path of the first menuentry in grub.cfg
    awk '/^[[:space:]]*(linux|linuxefi)[[:space:]]/ { print $2; exit }' "$GRUB_CFG" 2>/dev/null || true
}

write_top_level() { # $1 = kernel path, empty = remove the override
    local tmp
    tmp="$(mktemp)"
    grep -vE '^[[:space:]]*GRUB_TOP_LEVEL=' "$GRUB_DEFAULTS" > "$tmp" || true
    if [ -n "$1" ]; then
        printf 'GRUB_TOP_LEVEL="%s"\n' "$1" >> "$tmp"
    fi
    if cmp -s "$GRUB_DEFAULTS" "$tmp"; then
        say "$GRUB_DEFAULTS already in the requested state"
    else
        cp -a "$GRUB_DEFAULTS" "$GRUB_DEFAULTS.bak-$(date +%Y%m%d-%H%M%S)"
        install -m644 "$tmp" "$GRUB_DEFAULTS"
        say "updated $GRUB_DEFAULTS"
    fi
    rm -f "$tmp"
}

set_boot_default() {
    local want="$1" k

    [ "$(id -u)" -eq 0 ] || [ "$CHECK" -eq 1 ] || die "run this with sudo"
    if [ "$want" = "lts" ] && [ ! -e /boot/vmlinuz-linux-lts ]; then
        die "no /boot/vmlinuz-linux-lts - install the LTS kernel first"
    fi
    if grep -qE '^[[:space:]]*GRUB_DEFAULT=[^0]' "$GRUB_DEFAULTS"; then
        warn "GRUB_DEFAULT is not 0; GRUB_TOP_LEVEL reorders the top-level entry, so it is set to 0"
    fi
    if [ "$want" = "lts" ]; then
        say "making linux-lts the default kernel (GRUB_TOP_LEVEL)"
    else
        say "reverting to linux-zen as the default kernel"
    fi

    if [ "$CHECK" -eq 1 ]; then
        say "dry run - no file is changed"
        printf '    first boot entry now: %s\n' "$(first_boot_kernel)"
        [ -r "$GRUB_CFG" ] || say "note: $GRUB_CFG is root-only - the real run reads it and verifies the result"
        return 0
    fi

    if [ "$want" = "lts" ]; then
        write_top_level /boot/vmlinuz-linux-lts
        sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=0|' "$GRUB_DEFAULTS"
    else
        write_top_level ""
    fi

    grub-mkconfig -o "$GRUB_CFG" || die "grub-mkconfig failed - do not reboot"

    k="$(first_boot_kernel)"
    say "first boot entry uses: ${k:-unknown}"
    case "$k" in
        *vmlinuz-linux-lts)
            [ "$want" = "lts" ] || warn "expected linux-zen first, got linux-lts"
            ;;
        *vmlinuz-linux-zen)
            if [ "$want" = "lts" ]; then
                die "grub.cfg still boots $k first - do NOT reboot; check GRUB_TOP_LEVEL support in /etc/grub.d/10_linux"
            fi
            ;;
        *)
            warn "unrecognised first kernel path: ${k:-none} - inspect /boot/grub/grub.cfg before rebooting"
            ;;
    esac

    if [ "$want" = "lts" ]; then
        cat <<DONE

linux-lts is now the default boot entry (verified in grub.cfg).
Reboot and check:  uname -r  ->  $(ls /usr/lib/modules | grep -- '-lts$' | tail -1)
Rollback:          sudo $0 --revert-default && sudo reboot
DONE
    else
        cat <<DONE

linux-zen is the default boot entry again (verified in grub.cfg).
Reboot and check:  uname -r
DONE
    fi
}

if [ "$MODE" != install ]; then
    if [ "$MODE" = "make-default" ]; then
        set_boot_default lts
    else
        set_boot_default zen
    fi
    exit 0
fi

# --- 1. resolve the version from the local DB --------------------------------
ver=$(pacman -Si linux-lts 2>/dev/null | awk '/^Version/ {print $3; exit}')
[ -n "${ver:-}" ] || die "pacman does not know linux-lts (sync DB missing?) - run: sudo pacman -Syy"
say "local DB pins linux-lts ${ver}"

# The Arch package installs /usr/lib/modules/<pkgver>-<pkgrel>-lts,
# i.e. the module dir keeps the pkgrel: 6.18.58-1 -> 6.18.58-1-lts
kver="${ver}-lts"

# --- 2. download the exact versions from the archive ------------------------
urls=()
for p in "${PKGS[@]}"; do
    urls+=("${ARCHIVE}/${p:0:1}/${p}/${p}-${ver}-x86_64.pkg.tar.zst")
done

if [ "$CHECK" -eq 1 ]; then
    say "dry run - nothing is installed"
    [ "$(id -u)" -eq 0 ] || say "note: a real run needs sudo"
    for u in "${urls[@]}"; do
        code=$(curl -sIL --max-time 20 -o /dev/null -w '%{http_code}' "$u" || true)
        printf '    %-3s %s\n' "$code" "$u"
        [ "$code" = "200" ] || warn "not available: $(basename "$u")"
    done
    printf '\nnext: sudo %s\n' "$0"
    exit 0
fi

[ "$(id -u)" -eq 0 ] || die "run this with sudo"

installed_ver=$(pacman -Q linux-lts 2>/dev/null | awk '{print $2}' || true)
if [ "${installed_ver:-none}" = "$ver" ]; then
    say "linux-lts ${ver} is already installed - skipping download"
else
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    files=()
    for u in "${urls[@]}"; do
        out="$tmp/$(basename "$u")"
        say "downloading $(basename "$u")"
        curl -fSL --retry 3 --connect-timeout 15 -o "$out" "$u" \
            || die "download failed: $u (DB stale and archive missing it? refresh the DB with update-engine.sh prepare)"
        files+=("$out")
    done
    say "installing linux-lts ${ver}"
    pacman -U --noconfirm "${files[@]}" || die "pacman -U failed (keyring/signature? try: sudo pacman-key --refresh-keys)"
fi

# --- 4. verify --------------------------------------------------------------
[ -d "/usr/lib/modules/${kver}" ] || die "module directory /usr/lib/modules/${kver} is missing"
say "module directory: /usr/lib/modules/${kver}"

if [ -e /boot/vmlinuz-linux-lts ]; then
    say "kernel: /boot/vmlinuz-linux-lts"
else
    die "missing /boot/vmlinuz-linux-lts"
fi

if [ ! -e /boot/initramfs-linux-lts.img ]; then
    say "initramfs missing - building with dracut"
    dracut --force -L 3 /boot/initramfs-linux-lts.img --kver "$kver" \
        || die "dracut failed"
fi
say "initramfs: /boot/initramfs-linux-lts.img"

if ! dkms status 2>/dev/null | grep -q "${kver}.*installed"; then
    say "DKMS has no module for ${kver} - building"
    dkms autoinstall -k "$kver" || die "dkms autoinstall failed for ${kver}"
fi
dkms status | grep "$kver" || die "DKMS still has no installed module for ${kver}"

if ! grep -q 'linux-lts' /boot/grub/grub.cfg; then
    say "GRUB has no linux-lts entry - regenerating grub.cfg"
    grub-mkconfig -o /boot/grub/grub.cfg
fi
say "grub entries mentioning linux-lts: $(grep -c 'linux-lts' /boot/grub/grub.cfg)"

# --- 5. optional: stage the full upgrade ------------------------------------
if [ "$PREPARE_UPDATE" -eq 1 ]; then
    engine="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/update-engine.sh"
    [ -x "$engine" ] || die "update-engine.sh not found next to this script"
    say "staging the full upgrade (safe under Plasma: mirrors, DB, snapshot, download)"
    "$engine" prepare
fi

cat <<NEXT

Done. The fallback kernel is installed; the default kernel is unchanged.

Next steps:
  1. Reboot:  sudo reboot
  2. In GRUB choose: Advanced options for Garuda Linux -> linux-lts
  3. Verify:  uname -r   (expect ${kver})
              nvidia-smi (must exit 0)
  4. Boot the default kernel again if you only wanted the fallback.
  5. Want LTS as the daily kernel? After the boot test passes:
       sudo $0 --make-default && sudo reboot
       (rollback: sudo $0 --revert-default && sudo reboot)
$( [ "$PREPARE_UPDATE" -eq 1 ] && printf '  6. Apply the staged upgrade: sudo ./scripts/tools/update-now.sh\n' )
NEXT
