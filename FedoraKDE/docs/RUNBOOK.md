# RUNBOOK — install day

Order matters. Do not reorder the TPM2 step.

## 0. Prerequisites

- A fresh backup: `scripts/backup.sh` (the kit refuses a tarball older than 72 h
  only with a warning; a missing tarball is fatal).
- A USB stick **≥ 8 GiB** (live ISO is 3.4 GiB).
- The ISO: `Fedora-KDE-Desktop-Live-45-1.4.x86_64.iso` on the WD drive
  (`LinuxDCO/`), checksum verified by `preflight`.
- Network on the new system (Wi-Fi is fine after first boot; the netinstall
  mode wants a cable).
- Secure Boot **enabled** in BIOS for the hardened path
  (ASUS: Security → Secure Boot Control → Enabled, default keys installed).

## 1. Preflight (current Garuda system, ~2–5 min)

```bash
cd /path/to/garuda-restore/FedoraKDE
sudo ./install.sh preflight
```

The manifest lists home usage, what the tarball actually contains, and every
large directory that is **not** preserved. Copy anything you need first, then:

```bash
sudo ./install.sh preflight --accept-manifest
```

Hard failures (missing/small backup, wrong target model, missing ISO) stop here.

## 2. Build the USB (~3–5 min, writes only the USB)

```bash
sudo ./install.sh usb --device /dev/sdX --mode live --yes
```

It writes the ISO, relocates the backup GPT, adds a 128 MiB FAT partition
labelled `OEMDRV`, copies `ks.cfg`, `FedoraKDE.tar.gz` and verifies the
payload by re-mounting it.

`--mode netinstall` instead downloads the Everything netinst ISO and produces a
zero-touch installer.

## 3. Install (10–20 min)

1. Reboot, press **F12**, choose the USB.
2. **live mode:** on the desktop click **Install to Hard Drive**.
   **netinstall mode:** do nothing — Anaconda starts by itself.
3. Anaconda reads the kickstart from `OEMDRV`: it wipes **nvme1n1**, creates
   ESP + /boot + LUKS2/btrfs, creates user `ldco`, sets the locale and
   bootloader, then copies the provisioning bundle to `/root/FedoraKDE`.

## 4. First boot — provisioning (15–40 min, network)

Log in as `ldco`, connect to Wi-Fi, then:

```bash
sudo /root/FedoraKDE/install.sh provision --yes
```

If you built the USB with `--auto-provision`, a systemd unit does this at boot;
the manual command is still the documented path and is safe to re-run.

Stages: `repos → base → nvidia → asus → security-baseline → snapshots → ux →
apps → shell → finalize`. Each one writes a marker; re-running skips finished
stages.

## 5. MOK enrollment (one reboot)

The `nvidia` stage prints the instruction and stops. Reboot:

1. blue **MOK Manager** screen appears
2. **Enroll MOK → Continue → Yes**
3. enter the MOK password (interactive run: the one you typed; auto run:
   `/etc/fedora-kde/mok-password`)
4. **Reboot**

Check: `lsmod | grep '^nvidia '` and `nvidia-smi` must work.

Then resume:

```bash
sudo /root/FedoraKDE/install.sh provision --yes
```

## 6. TPM2 auto-unlock (LAST)

Only after Secure Boot is on, MOK is enrolled and the nvidia module loads:

```bash
sudo /root/FedoraKDE/install.sh tpm2-enroll --yes
sudo reboot
```

The passphrase keyslot is retained as recovery. Rollback:
`sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme1n1p3`.

## 7. Verify

```bash
sudo /root/FedoraKDE/install.sh verify --expect-tpm2
```

16 checks; exit 0 only if none FAIL. `SKIP` is only used for the PRIME check
when no graphical session is available.

## 8. Aftercare

- Reboot once more and confirm: KDE panels, NVIDIA idle power, `asusctl profile -p`.
- Erase the `OEMDRV` partition (it held the user hash and possibly the LUKS
  passphrase): `sudo sgdisk -d 3 /dev/sdX`.
- Keep the backup tarball and the Garuda ISO on the WD drive.
