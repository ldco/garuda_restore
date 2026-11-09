# HARDWARE — ASUS TUF Gaming F15 FX507ZR

| Component | Detail |
|---|---|
| CPU | Intel Core i7-12700H, 14C/20T (6P+8E), Alder Lake |
| iGPU | Intel Iris Xe (Alder Lake-P GT2), `8086:46a6`, drives the internal panel |
| dGPU | NVIDIA RTX 3070 Mobile / Max-Q 8 GB, `10de:249d`, GA104 |
| RAM | 30 GiB usable (32 GiB DDR5) |
| Storage | `nvme1n1` Intel SSDPEKNU512GZ 512 GB (system); `nvme0n1` WD Blue SN570 1 TB (repo + backups) |
| Network | Intel AX201 Wi-Fi 6 + Bluetooth 5.1, 2.5 GbE |
| Ports | Thunderbolt 4 / USB-C, HDMI, 2.5 GbE, USB-A |
| TPM | TPM 2.0 (`/dev/tpm0`) |
| Battery | 65.6 / 90.0 Wh (72.9 % health, 2026-11) |
| Displays | eDP-2 (internal, Intel) + DP-1 + HDMI-A-1 (NVIDIA) |
| Firmware | Secure Boot currently disabled; LVFS-capable (fwupd) |

## Quirks

- Hybrid graphics: the internal panel is wired to the **Intel** GPU. Do not set
  `KWIN_DRM_DEVICES` to the NVIDIA card — the internal display disappears.
- Sleep is unstable on this combination (14 documented attempts). See
  `docs/SLEEP-POLICY.md`.
- The CPU fan does not respond to custom asusctl fan curves; BIOS control is
  kept. GPU fan curves work.
- Device names (`nvme0`/`nvme1`) can swap between boots. **Always** resolve via
  `/dev/disk/by-id` and the `%pre` model assertion.
