#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

custom_file="/etc/grub.d/40_custom"
backup_file="/etc/grub.d/40_custom.bak.pre-codex-s2idle"
start_marker="### BEGIN Codex s2idle workaround ###"
end_marker="### END Codex s2idle workaround ###"

cmdline=$(< /proc/cmdline)
boot_image=$(sed -n 's/.*BOOT_IMAGE=\([^ ]*\).*/\1/p' /proc/cmdline)

if [[ -z "${boot_image}" ]]; then
  echo "Could not determine BOOT_IMAGE from /proc/cmdline." >&2
  exit 1
fi

linux_args="${cmdline#BOOT_IMAGE=${boot_image} }"
linux_args=$(printf '%s\n' "${linux_args}" | sed -E 's/(^| )mem_sleep_default=[^ ]+//g; s/  +/ /g; s/^ //; s/ $//')
linux_args="${linux_args} mem_sleep_default=s2idle"

boot_dir=${boot_image%/*}
kernel_base=${boot_image##*/}
kernel_flavor=${kernel_base#vmlinuz-}

initrds=()
if [[ -f /boot/intel-ucode.img ]]; then
  initrds+=("${boot_dir}/intel-ucode.img")
fi
if [[ -f /boot/amd-ucode.img ]]; then
  initrds+=("${boot_dir}/amd-ucode.img")
fi

main_initrd="${boot_dir}/initramfs-${kernel_flavor}.img"
if [[ ! -f "/boot/initramfs-${kernel_flavor}.img" ]]; then
  echo "Expected initramfs /boot/initramfs-${kernel_flavor}.img was not found." >&2
  exit 1
fi
initrds+=("${main_initrd}")

cp -an "${custom_file}" "${backup_file}"

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

cat >> "${tmp_file}" <<EOF
${start_marker}
menuentry 'Garuda Linux (s2idle suspend workaround)' --class garuda --class gnu-linux --class gnu --class os {
    load_video
    set gfxpayload=keep
    insmod gzio
    search --no-floppy --fs-uuid --set=root 11640019-27f8-48af-b0cc-108f5b2da88e
    echo 'Loading Linux ${kernel_flavor} (s2idle workaround) ...'
    linux   ${boot_image} ${linux_args}
    echo 'Loading initial ramdisk ...'
    initrd  ${initrds[*]}
}
${end_marker}
EOF

install -m 0755 "${tmp_file}" "${custom_file}"
grub-mkconfig -o /boot/grub/grub.cfg

cat <<'EOF'
Added a separate GRUB entry:
  Garuda Linux (s2idle suspend workaround)

Your current default entry was not changed.
On the next reboot, open the GRUB menu and boot that entry to test suspend/resume.
EOF
