# PARTITIONING

Target: `nvme1n1` (Intel SSDPEKNU512GZ, 512 GB). The WD SN570 is never touched.

```
/dev/nvme1n1  (477 GiB usable)
├─ p1  1 GiB   vfat   /boot/efi        label EFI
├─ p2  1 GiB   ext4   /boot            Fedora standard, not snapshotted
└─ p3  rest    LUKS2  (argon2id)       passphrase + later a TPM2 (PCR 7) keyslot
   └─ btrfs volume, label "fedora"
      ├─ @          → /
      ├─ @home      → /home
      ├─ @log       → /var/log
      ├─ @cache     → /var/cache
      ├─ @srv       → /srv
      ├─ @root      → /root
      └─ @var-tmp   → /var/tmp
```

Mount options: `noatime,compress=zstd:3,ssd,discard=async,space_cache=v2`
(applied to the btrfs lines by the kickstart `%post`).

Swap: zram (`min(ram,16384)`, zstd) is primary. A 32 GiB `/swap/swapfile`
(`btrfs filesystem mkswapfile`) is created by the `base` stage for OOM
headroom; hibernation is **not** enabled.

## Why a separate /boot

Fedora's installer and GRUB are tested with a separate ext4 `/boot`. Keeping it
separate removes the GRUB-btrfs+zstd failure mode entirely. The cost: kernel and
initramfs are not part of a root snapshot. If you want full kernel rollback
later, the documented opt-in is to move `/boot` into `@` and `chattr +C /boot`
so GRUB never has to decompress zstd.

## What the old disk looked like

ESP was 300 MiB (only 1.2 MiB used, GRUB only) and `/boot` lived inside `@`.
The new 1 GiB ESP leaves headroom for kernels, initramfs, fwupd capsules and a
future UKI.
