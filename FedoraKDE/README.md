# FedoraKDE — Fedora 45 KDE migration kit

Target machine: **ASUS TUF Gaming F15 FX507ZR** (i7-12700H, RTX 3070 Mobile,
30 GiB RAM, TPM2), currently running Garuda Linux KDE Plasma 6.8.1.
Goal: Fedora 45 KDE Plasma 6.8.2 with the same desktop experience, the same
hybrid-GPU behaviour, a hardened baseline, and a sleep policy that cannot
hard-freeze the laptop.

Everything is driven by one entrypoint:

```bash
./install.sh <stage> [options]
```

| Stage | Runs on | What it does |
|---|---|---|
| `preflight` | current Garuda | backup integrity, **blocking data-triage manifest**, disk/ISO guards, Secure Boot + TPM2 report |
| `usb` | current Garuda (root) | writes the Fedora ISO to a USB and adds a FAT partition labelled `OEMDRV` holding `ks.cfg` + the provisioning bundle |
| `provision` | new Fedora, first boot (root) | repos, NVIDIA + MOK, ASUS tools, hardening, snapshots, UX restore, apps, shell, finalize |
| `tpm2-enroll` | new Fedora, **last** | `systemd-cryptenroll --tpm2-pcrs=7` on the root LUKS device |
| `verify` | new Fedora | 16 read-only acceptance checks, `PASS/FAIL/SKIP` table |

Read [`docs/RUNBOOK.md`](docs/RUNBOOK.md) before touching a disk.

## The 4-step flow

```bash
# 1. on the current Garuda system
sudo ./install.sh preflight                 # review the manifest, then:
sudo ./install.sh preflight --accept-manifest

# 2. build the installer USB (destroys the USB stick, nothing else)
sudo ./install.sh usb --device /dev/sdX --mode live --yes

# 3. boot the USB (F12), click "Install to Hard Drive" (live mode)
#    netinstall mode installs with no interaction at all

# 4. on the new Fedora system
sudo /root/FedoraKDE/install.sh provision --yes
sudo reboot                                  # enroll the MOK key in the blue screen
sudo /root/FedoraKDE/install.sh tpm2-enroll --yes
sudo /root/FedoraKDE/install.sh verify --expect-tpm2
```

## Safety guarantees

- The kickstart has `ignoredisk --only-use=nvme1n1`, a `%pre` model assertion
  (`INTEL SSDPEKNU512GZ`) and a size assertion. The WD Blue SN570 that holds
  this repository and the backups can never be selected.
- `usb` refuses `/dev/nvme*`, the WD serial, mounted devices and anything
  smaller than 8 GiB; the exact device path must be typed (or `--yes`).
- `preflight` refuses to continue until the data-triage manifest is accepted.
- Secrets (LUKS passphrase, user password) are read with `read -rs`, kept in a
  `umask 077` temp dir, never written to the repo or the log, and the temp dir
  is wiped by a trap. Use `--prompt-luks-at-install` to keep the LUKS
  passphrase off the USB entirely.
- Every stage is idempotent (markers in `/var/log/fedora-kde/state/`).

## Modes

- `--mode live` (default): fast local install from the KDE live ISO; one click
  starts Anaconda, which then reads `ks.cfg` from `OEMDRV` and installs
  unattended. No network is needed during the install.
- `--mode netinstall`: downloads the Fedora Everything netinst ISO; Anaconda
  starts by itself and `%packages` applies. Fully unattended, but needs a
  wired network during the install.

## Non-goals

Hibernation by default, supergfxctl, MUX automation, fapolicyd/usbguard/AIDE
enabled by default, reimplementing Garuda's packages, any write to
`nvme0n1`, any change to the current Garuda boot configuration, Windows
dual-boot.

## Tests

```bash
./tests/shellcheck.sh      # shellcheck -S warning over every script
./tests/ksvalidator.sh     # renders both kickstarts, validates them in Fedora 45
./tests/dry-run.sh         # refusal logic + secret hygiene (fixtures, no devices)
```
