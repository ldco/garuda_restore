#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

custom_file="/etc/grub.d/40_custom"
start_marker="### BEGIN Codex s2idle workaround ###"
end_marker="### END Codex s2idle workaround ###"

tmp_file=$(mktemp)
cleanup() {
  rm -f "${tmp_file}"
}
trap cleanup EXIT

awk -v start="${start_marker}" -v end="${end_marker}" '
  $0 == start { skip=1; next }
  $0 == end { skip=0; next }
  !skip { print }
' "${custom_file}" > "${tmp_file}"

install -m 0755 "${tmp_file}" "${custom_file}"
grub-mkconfig -o /boot/grub/grub.cfg

echo "Removed the Codex s2idle workaround entry from GRUB."
