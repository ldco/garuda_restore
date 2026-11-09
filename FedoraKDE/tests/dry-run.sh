#!/usr/bin/env bash
# Test: refusal logic + secret hygiene, using fixtures and --dry-run.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

LOG="$TMP/log"
HOME_F="$TMP/home"
BK="$TMP/backups"
ISO="$TMP/Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso"
mkdir -p "$HOME_F/Documents" "$HOME_F/.cache" "$BK" "$LOG"
echo notes >"$HOME_F/Documents/notes.txt"
dd if=/dev/zero of="$HOME_F/.cache/blob" bs=1M count=2 status=none
truncate -s 3543603200 "$ISO"

# minimal fake backup with the expected layout
mkdir -p "$TMP/fake/config" "$TMP/fake/dotfiles" "$TMP/fake/.fonts" "$TMP/fake/wallpapers" "$TMP/fake/packages"
echo x >"$TMP/fake/config/kdeglobals"
echo x >"$TMP/fake/dotfiles/.bashrc"
echo x >"$TMP/fake/.fonts/Test.ttf"
echo x >"$TMP/fake/wallpapers/w.png"
echo x >"$TMP/fake/packages/explicitly-installed.txt"
tar -czf "$BK/garuda-backup-2026-11-09_00-04-last.tar.gz" -C "$TMP" fake

export FEDORA_KDE_LOG_DIR="$LOG"
export FEDORA_KDE_STATE_DIR="$LOG/state"
export FEDORA_KDE_HOME="$HOME_F"
export FEDORA_KDE_BACKUP_DIR="$BK"
export FEDORA_KDE_ISO="$ISO"
export FEDORA_KDE_TARGET=/dev/nvme1n1
TARGET_MODEL="$(cat /sys/block/nvme1n1/device/model 2>/dev/null | xargs || true)"
export FEDORA_KDE_TARGET_MODEL="$TARGET_MODEL"

fail=0
expect_fail() { # name pattern command...
  local name="$1" pattern="$2"
  shift 2
  local out="$TMP/$name.out"
  if "$@" >"$out" 2>&1; then
    echo "FAIL: $name should have refused" >&2
    fail=1
    return
  fi
  if ! grep -qi -- "$pattern" "$out"; then
    echo "FAIL: $name refused but did not mention '$pattern'" >&2
    sed -n '1,20p' "$out" >&2
    fail=1
    return
  fi
  echo "ok: $name refused ($pattern)"
}

expect_ok() {
  local name="$1"
  shift
  local out="$TMP/$name.out"
  if ! "$@" >"$out" 2>&1; then
    echo "FAIL: $name should have succeeded" >&2
    sed -n '1,40p' "$out" >&2
    fail=1
    return
  fi
  echo "ok: $name succeeded"
}

expect_fail preflight-no-accept 'manifest' "$ROOT/install.sh" preflight --dry-run
expect_ok preflight-accept "$ROOT/install.sh" preflight --dry-run --accept-manifest

export FEDORA_KDE_LUKS_ENV=FK_TEST_LUKS
export FEDORA_KDE_PASS_ENV=FK_TEST_PASS
export FK_TEST_LUKS='correct-horse-battery-staple'
export FK_TEST_PASS='dummy-user-password'

expect_fail usb-nvme 'nvme' "$ROOT/install.sh" usb --device /dev/nvme1n1 --dry-run --iso "$ISO"
if [[ -b /dev/nvme0n1 ]]; then
  expect_fail usb-wd 'WD SN570' "$ROOT/install.sh" usb --device /dev/nvme0n1 --dry-run --iso "$ISO"
fi
FEDORA_KDE_SELFTEST=1 FEDORA_KDE_TEST_MOUNTED=/dev/fakeusb0 \
  expect_fail usb-mounted 'mounted' "$ROOT/install.sh" usb --device /dev/fakeusb0 --dry-run --iso "$ISO"

if grep -Rq "$FK_TEST_LUKS" "$LOG" 2>/dev/null; then
  echo "FAIL: LUKS passphrase leaked into the logs" >&2
  fail=1
else
  echo "ok: no secret in the logs"
fi

if (( fail )); then
  echo "dry-run tests FAILED" >&2
  exit 1
fi
echo "dry-run tests passed"
