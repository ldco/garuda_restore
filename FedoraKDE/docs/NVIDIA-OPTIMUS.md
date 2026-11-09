# NVIDIA OPTIMUS

## Model

- Intel iGPU drives **all displays** (internal eDP-2 + external DP/HDMI are
  mixed on this laptop; KWin composites on Intel).
- RTX 3070 Mobile is a render-offload device, powered down when idle.

## What the kit installs

```bash
akmod-nvidia                    # open kernel modules (Ampere)
xorg-x11-drv-nvidia-cuda        # CUDA/NVENC user space
nvidia-prime-rtd3pm             # runtime D3 power management
switcheroo-control              # KDE "Launch using Discrete GPU"
```

`nvidia-prime-rtd3pm` is resolved at runtime; if it is missing the script logs
`ALT` and installs `xorg-x11-drv-nvidia-power` instead.

## Runtime configuration

| Setting | Location | Value |
|---|---|---|
| Kernel mode setting | `/etc/default/grub` + BLS | `nvidia_drm.modeset=1` |
| nouveau | GRUB | `rd.driver.blacklist=nouveau modprobe.blacklist=nouveau` |
| KWin direct scanout | `/etc/environment` | `KWIN_DRM_NO_DIRECT_SCANOUT=1` |
| PowerDevil DDC | `~/.config/environment.d/kwin-fixes.conf` | `POWERDEVIL_NO_DDCUTIL=1` |

Per-application offload:

```bash
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia <app>
```

## Never do

| Setting | Consequence |
|---|---|
| `nvidia_drm.fbdev=1` | GPU stuck at ~40 W, 96 °C, thermal shutdown (measured on this laptop) |
| `NVreg_EnableGpuFirmware=0` (driver ≥ 610) | VRAM corruption after sleep/wake |
| `KWIN_DRM_DEVICES=<nvidia>` | internal display breaks |
| `supergfxctl` | phased out upstream; not installed |
| `mem_sleep_default=deep` | atomic modeset failures, thermal cascade |

## Verify

```bash
nvidia-smi --query-gpu=name,pstate,power.draw --format=csv
lsmod | grep '^nvidia '
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glxinfo -B | head -5
asusctl -v
```

Expected idle: P5/P8 and a few watts; `supported` PRIME offload lists NVIDIA.
