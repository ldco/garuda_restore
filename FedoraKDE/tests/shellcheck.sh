#!/usr/bin/env bash
# Test: shellcheck -S warning over every script in the kit.
set -Eeuo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"

SC="${SHELLCHECK:-}"
if [[ -z "$SC" ]]; then
  if command -v shellcheck >/dev/null 2>&1; then
    SC=shellcheck
  elif [[ -x /tmp/nocowboy/shellcheck ]]; then
    SC=/tmp/nocowboy/shellcheck
  elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "using docker shellcheck image"
    docker run --rm -v "$ROOT:/mnt:ro" koalaman/shellcheck:stable \
      -S warning /mnt/install.sh /mnt/scripts/*.sh /mnt/scripts/lib/*.sh
    exit $?
  else
    echo "SKIP: shellcheck not installed (set SHELLCHECK=/path/to/shellcheck)" >&2
    exit 0
  fi
fi

mapfile -t files < <(find "$ROOT" -type f -name '*.sh' | sort)
echo "shellcheck ${#files[@]} files"
"$SC" -S warning "${files[@]}"
