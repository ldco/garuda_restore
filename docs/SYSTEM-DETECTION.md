# System Detection Report

**Generated:** 2025-12-29
**Hostname:** ldco-garuda
**Uptime:** 1d 2h 23m

---

## Operating System

| Property | Value |
|----------|-------|
| **Distribution** | Garuda Linux (Arch-based) |
| **Desktop** | KDE Plasma 6.5.4 |
| **Window Manager** | KWin Wayland |
| **Display Manager** | SDDM |
| **Kernel** | 6.18.2-zen2-1-zen (ZEN Kernel) |
| **Init System** | systemd v259 |
| **Architecture** | x86_64 |

---

## Hardware

### System

| Property | Value |
|----------|-------|
| **Type** | Laptop |
| **Manufacturer** | ASUSTeK |
| **Model** | ASUS TUF Gaming F15 FX507ZR |
| **BIOS** | American Megatrends LLC. v FX507ZR.316 (2023-05-03) |

### CPU

| Property | Value |
|----------|-------|
| **Model** | 12th Gen Intel Core i7-12700H |
| **Architecture** | Alder Lake (Hybrid) |
| **Cores** | 14 (6 P-cores + 8 E-cores) |
| **Threads** | 20 |
| **Base/Max Frequency** | 400 MHz - 4700 MHz |
| **Cache** | L1: 1.2 MiB, L2: 11.5 MiB, L3: 24 MiB |
| **Features** | AVX2, AES-NI, VT-x, SSE4.2 |

### Memory

| Property | Value |
|----------|-------|
| **Total** | 32 GB DDR5 |
| **Available** | 30.96 GB |
| **Used** | ~22 GB (71.8%) |
| **Swap** | 31 GB (zram compressed) |
| **Swap Used** | 6.3 GB (20.4%) |
| **Swappiness** | 133 (high, using zram) |

### Graphics

#### Intel Integrated GPU
| Property | Value |
|----------|-------|
| **Model** | Intel Alder Lake-P GT2 Iris Xe Graphics |
| **Driver** | i915 (kernel) |
| **Status** | Active on eDP-2 (laptop display) |

#### NVIDIA Discrete GPU
| Property | Value |
|----------|-------|
| **Model** | NVIDIA GeForce RTX 3070 Mobile / Max-Q |
| **VRAM** | 8192 MB GDDR6 |
| **Driver** | 590.48.01 (proprietary) |
| **CUDA** | 13.1 |
| **Temperature** | 56C |
| **Power** | 25W / 115W TDP |
| **Status** | Active on DP-1, HDMI-A-1 (external monitors) |

### Displays

| Display | Resolution | Refresh | Scale | Type |
|---------|------------|---------|-------|------|
| eDP-2 (Laptop) | 2560x1440 | 165 Hz | 150% | 15.5" ChiMei InnoLux |
| DP-1 (External) | 2560x1440 | 165 Hz | 125% | 27" AQ27H1 |
| HDMI-A-1 (External) | 2560x1440 | 144 Hz | 125% | 27" AQ27H1 |

**Total Desktop Resolution:** 7680x1440 (triple monitor)

### Storage

| Device | Size | Type | Model | Mount | Filesystem |
|--------|------|------|-------|-------|------------|
| nvme0n1 | 477 GB | NVMe SSD | Intel SSDPEKNU512GZ | / (system) | Btrfs |
| nvme1n1 | 932 GB | NVMe SSD | WD Blue SN570 1TB | /run/media/.../working | ext4 |
| sda | 1.82 TB | USB HDD | WD20NPVZ | (external backup) | LUKS encrypted |
| sdd | 29 GB | USB Flash | Kingston DataTraveler 3.0 | - | FAT32 |

#### Btrfs Subvolumes (nvme0n1p2)
- `@` -> `/`
- `@home` -> `/home`
- `@root` -> `/root`
- `@srv` -> `/srv`
- `@cache` -> `/var/cache`
- `@log` -> `/var/log`
- `@tmp` -> `/var/tmp`

#### Disk Usage
| Mount | Used | Available | Use% |
|-------|------|-----------|------|
| / (btrfs) | 188 GB | 289 GB | 40% |
| /run/media/.../working | 582 GB | 288 GB | 67% |

### Network

| Interface | Type | State | Speed | MAC |
|-----------|------|-------|-------|-----|
| eno2 | Intel I219-LM Ethernet | UP | 1000 Mbps | (filtered) |
| wlo1 | Intel AX201 WiFi 6 | DOWN | - | (filtered) |

**IP Address:** 192.168.1.5/24

### Audio

| Device | Driver |
|--------|--------|
| Intel Alder Lake PCH-P HD Audio | snd_hda_intel |
| NVIDIA GA104 HD Audio | snd_hda_intel |
| HP HyperX Virtual Surround | snd-usb-audio |
| ASUS C-Media Audio | snd-usb-audio |

**Audio Server:** PipeWire 1.4.9 (with PulseAudio compatibility)

### Peripherals

| Device | Type |
|--------|------|
| Logitech MX Master 3 | Bluetooth Mouse |
| Sonix USB2.0 HD UVC WebCam | Integrated Camera |
| Intel AX201 Bluetooth 5.2 | Bluetooth Adapter |

### Battery

| Property | Value |
|----------|-------|
| **Model** | ASUS A32-K55 |
| **Capacity** | 70.1 / 90 Wh (77.9% health) |
| **Status** | Full (plugged in) |
| **Voltage** | 16.52V |

---

## Software

### Package Management

| Property | Value |
|----------|-------|
| **Package Manager** | pacman |
| **Explicitly Installed** | 335 packages |
| **AUR Packages** | 9 packages |
| **Orphan Packages** | 0 |

### Repositories

1. garuda (chaotic-mirrorlist)
2. core
3. extra
4. multilib
5. chaotic-aur

### Key Services Running

| Service | Description |
|---------|-------------|
| NetworkManager | Network management |
| mullvad-daemon | Mullvad VPN |
| sddm | Display manager |
| smb/nmb | Samba file sharing |
| cups | Printing |
| bluetooth | Bluetooth support |
| power-profiles-daemon | Power management |
| systemd-oomd | OOM killer |
| ollama | Local AI inference |

### Development Tools

| Tool | Version |
|------|---------|
| GCC | 15.2.1 |
| Clang | 21.1.6 |
| Python | (via conda/system) |
| Node.js | (via nvm) |
| Rust/Cargo | (installed) |
| Docker | (installed) |

### Browsers Running

- Brave Browser
- Google Chrome
- Chromium

### IDE/Editors

- Visual Studio Code
- (multiple instances)

---

## Thermal Status

| Sensor | Temperature | Status |
|--------|-------------|--------|
| CPU Package | 64C | Normal |
| CPU Cores | 60-64C | Normal |
| DDR5 DIMM 1 | 60.2C | HIGH (threshold 55C) |
| DDR5 DIMM 2 | 60.2C | HIGH (threshold 55C) |
| NVMe SSD (WD) | 55.9C | Normal |
| NVIDIA GPU | 56C | Normal |
| WiFi Module | 44C | Normal |

### Fans
| Fan | Speed |
|-----|-------|
| CPU Fan | 2800 RPM |
| GPU Fan | 2600 RPM |

---

## Security

### VPN
- **Mullvad VPN:** Daemon running
- **Tailscale:** Not detected

### Firewall
- **firewall-applet:** Running (user session)
- **ufw/firewalld:** Not directly detected

### Encryption
- External backup drive: LUKS encrypted
- System drive: Not encrypted (Btrfs only)

### Listening Ports

| Port | Service |
|------|---------|
| 139, 445 | Samba (0.0.0.0) |
| 631 | CUPS (localhost) |
| 1716 | KDE Connect |
| 11434 | Ollama AI (localhost) |
| Various | VS Code debug ports |

---

## Kernel Parameters

```
BOOT_IMAGE=/@/boot/vmlinuz-linux-zen
root=UUID=11640019-27f8-48af-b0cc-108f5b2da88e
rw rootflags=subvol=@
quiet loglevel=3
```

---

## GRUB Configuration

```
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT='quiet loglevel=3'
GRUB_THEME="/usr/share/grub/themes/garuda-dr460nized/theme.txt"
GRUB_DISABLE_OS_PROBER=false
```

---

## File System Configuration (fstab)

| UUID | Mount | Type | Options |
|------|-------|------|---------|
| E83B-1EBE | /boot/efi | vfat | defaults,umask=0077 |
| 11640019-... | / | btrfs | subvol=/@,noatime,compress=zstd |
| 11640019-... | /home | btrfs | subvol=/@home,noatime,compress=zstd |
| - | /tmp | tmpfs | defaults,noatime,mode=1777 |

---

## VM/Virtualization

| Technology | Status |
|------------|--------|
| Intel VT-x | Enabled |
| Intel VMD RAID | Active |
| KVM | Available |
