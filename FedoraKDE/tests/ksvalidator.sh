#!/usr/bin/env bash
# Test: render both kickstarts with dummy secrets and run ksvalidator.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export FEDORA_KDE_LOG_DIR="$TMP/log"
mkdir -p "$TMP/live" "$TMP/net"

"$ROOT/scripts/build-usb.sh" --render-only --mode live --render-dir "$TMP/live"
"$ROOT/scripts/build-usb.sh" --render-only --mode netinstall --render-dir "$TMP/net"

if grep -qE '@[A-Z_]+@' "$TMP/live/ks.cfg" "$TMP/net/ks.cfg"; then
  echo "FAIL: unresolved template tokens" >&2
  exit 1
fi
echo "rendered kickstarts have no unresolved tokens"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "SKIP: docker unavailable; install pykickstart and run ksvalidator manually" >&2
  exit 0
fi

docker run --rm -v "$TMP:/w:ro" registry.fedoraproject.org/fedora:45 \
  sh -c 'dnf -y -q install pykickstart >/dev/null && ksvalidator /w/live/ks.cfg && ksvalidator /w/net/ks.cfg'
