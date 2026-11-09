# SECURE BOOT + TPM2

## Strict order (do not reorder)

1. **BIOS**: Security → Secure Boot Control → Enabled, install default keys.
2. **Install** Fedora (the kickstart).
3. **NVIDIA + MOK**: `provision` installs `akmod-nvidia`, fixes the akmods CA
   template, runs `kmodgenca -a -f`, rebuilds the module, then `mokutil --import`.
4. **Reboot** and enroll the key in the blue MOK screen.
5. **Verify** `lsmod | grep '^nvidia '`.
6. **TPM2 last**: `install.sh tpm2-enroll --yes`.

Why last: the TPM2 keyslot is bound to **PCR 7**, which measures the Secure
Boot state and the PK/KEK/db keys. Enabling Secure Boot or changing keys after
enrollment changes PCR 7 and the disk silently stops auto-unlocking.

## MOK

The akmods signing key lives in `/etc/pki/akmods/`. Fedora's default certificate
template can produce a certificate the `.machine` keyring refuses; the script
appends a `CA:TRUE` extension to `/etc/pki/akmods/cacert.config.in`, regenerates
the key with `kmodgenca -a -f`, and **verifies** `openssl x509 -text` shows
`CA:TRUE` before importing.

The private key is on the encrypted root — this is why full-disk encryption is a
prerequisite, not a nicety.

Auto-provisioning writes the one-time MOK password to
`/etc/fedora-kde/mok-password` (0600).

## TPM2 enrollment

```bash
systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme1n1p3
```

Only PCR 7 is bound: binding PCR 0/2/4 breaks unlock on every kernel, initramfs
or GRUB update.

## Checks

```bash
mokutil --sb-state
mokutil --test-key /etc/pki/akmods/certs/public_key.der
cryptsetup luksDump /dev/nvme1n1p3 | grep -A3 systemd-tpm2
```

## Rollback

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/nvme1n1p3
```

The passphrase keyslot is always retained. If TPM unlock ever fails, the
passphrase still boots the machine.
