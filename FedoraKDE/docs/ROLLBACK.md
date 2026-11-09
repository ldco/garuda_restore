# ROLLBACK — recovery

## 1. Boot a snapshot (no working system needed)

The root subvolume is snapshotted by snapper before every DNF transaction.
`grub-btrfs` adds a **Fedora snapshots** submenu to GRUB.

1. Reboot, hold **Esc** / spam **Shift** at the GRUB menu.
2. Choose *Fedora Linux snapshots* → pick the newest pre-update snapshot.
3. The snapshot boots read-only. Log in, inspect, then make it permanent:

```bash
# Fedora pins subvol=@ in fstab and on the kernel cmdline, so the plain
# `snapper rollback` command is silently ignored. Swap subvolumes instead:
sudo mount /dev/mapper/luks-XXXX /mnt
sudo btrfs subvolume snapshot /mnt/@ /mnt/@.broken
sudo btrfs subvolume snapshot /mnt/@snapshots/N/snapshot /mnt/@
sudo btrfs subvolume set-default /mnt/@
sudo reboot
```

`/boot` is a separate ext4 partition: kernels and initramfs are **not** in the
snapshots. A snapshot boot still uses the current kernel.

## 2. Live-USB chroot

1. Boot the Fedora KDE live USB.
2. Open a terminal:

```bash
lsblk                                   # find the LUKS partition
sudo cryptsetup open /dev/nvme1n1p3 fedora
sudo mkdir -p /mnt/root
sudo mount /dev/mapper/fedora /mnt/root
sudo mount /dev/nvme1n1p2 /mnt/root/boot
sudo mount /dev/nvme1n1p1 /mnt/root/boot/efi
sudo mount --bind /dev /mnt/root/dev
sudo mount --bind /proc /mnt/root/proc
sudo mount --bind /sys /mnt/root/sys
sudo chroot /mnt/root
# inside: dnf history undo last | dnf distro-sync | grub2-mkconfig -o /boot/grub2/grub.cfg
```

## 3. Full roll back to Garuda

The backup tarball contains user data only, not the OS. Reinstalling Garuda is a
separate procedure (the Garuda ISO is on the WD drive under `LinuxDCO/Deprec/`).

## 4. Undo individual stages

| Stage | Undo |
|---|---|
| `nvidia` | `dnf remove akmod-nvidia xorg-x11-drv-nvidia-cuda`; remove the GRUB params with `grubby --update-kernel=ALL --remove-args="nvidia_drm.modeset=1 rd.driver.blacklist=nouveau modprobe.blacklist=nouveau"` |
| `security-baseline` | `rm /etc/sysctl.d/99-nocowboy-hardening.conf`; `systemctl disable --now firewalld`; `rm /etc/systemd/zram-generator.conf` |
| `snapshots` | `snapper -c root delete-config`; `systemctl disable --now snapper-timeline.timer snapper-cleanup.timer grub-btrfsd` |
| `ux` | previous `~/.config` kept at `~/.config.fedora-prev` |
| `sleep-policy disable` | `sudo /root/FedoraKDE/scripts/sleep-policy.sh rollback` |
| `tpm2-enroll` | `systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme1n1p3` |
