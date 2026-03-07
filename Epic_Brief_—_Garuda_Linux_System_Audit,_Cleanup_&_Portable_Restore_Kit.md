# Epic Brief — Garuda Linux System Audit, Cleanup & Portable Restore Kit

## Summary

The owner of a Garuda Linux (Arch-based, KDE Plasma Wayland) system wants to perform a full, fresh-eyes audit of their live installation — covering packages, services, startup, config files, disk hygiene, performance, and security — and apply a moderate cleanup to reach a definitively clean, well-understood baseline. Once that clean state is established, the outcome is captured as a **hardware-agnostic, one-click portable restore kit**: scripts and documentation that can reproduce the same clean, optimised setup on any new machine regardless of hardware. The restore kit must auto-detect or conditionally apply hardware-specific settings rather than hardcoding values tied to the current laptop.

---

## Context & Problem

### Who is affected
A solo developer/power user who runs Garuda Linux as their primary OS with a demanding hardware profile (NVIDIA + Intel hybrid GPU, triple 1440p monitors, heavy dev workloads, AI tools). The system has been tuned incrementally over many sessions and has accumulated undocumented optimisations, stale config, disabled-but-present services, and gaps between what the repo documents and what actually exists on disk.

### Current pain points

| Pain point | Impact |
|---|---|
| System has been tweaked over many sessions — not all changes are still valid or necessary | Uncertainty about which settings are actually doing something |
| Installed packages were never audited for relevance after many rounds of install/test/abandon | Disk bloat, slower updates, larger restore surface |
| Services and autostart entries accumulate silently | Wasted RAM, slower boot, unnecessary attack surface |
| The existing restore kit (`restore.sh`) references real hardware specifics (device node paths, ASUS-only tools, NVIDIA-specific GRUB params) | Cannot be used safely on different hardware without manual editing |
| No clear separation between "what this machine needs" vs "what any Garuda machine needs" | Every new machine install requires re-doing manual work instead of running a script |

### Desired end state

1. **This machine**: clean, snappy, well-understood — every running service and installed package has a known reason to exist; no cache bloat, no orphan packages, no stale config
2. **Restore kit**: a repo in a state where cloning it and running one script on a fresh Garuda install produces a polished, optimised system — with hardware-specific steps clearly gated behind detection logic or documented prompts

---

## Scope

### In scope
- Full audit and moderate cleanup of: packages (pacman + AUR), systemd services (user + system), autostart, config files (`/etc`, `~/.config`), disk (caches, journals, logs), performance settings, security posture (firewall, SSH, open ports, Samba)
- Re-validation of all existing optimisations (KWin settings, Baloo, ZRAM, governor, GPU power, ananicy-cpp) — nothing treated as sacred
- Rewriting the restore kit to be hardware-agnostic, complete, and self-documenting

### Out of scope
- Kernel compilation or custom kernel patching
- Installing new applications beyond what the clean system requires
- CI/CD pipelines or automated testing infrastructure
- Production deployment or cloud infrastructure

---

## Success Criteria

- [ ] Running `check --deep` on this machine shows zero issues
- [ ] Running `update` on this machine leaves no orphans, no stale cache, no failed services
- [ ] Running the restore kit on a new (different-hardware) Garuda machine completes without errors and without requiring manual hardware-specific edits
- [ ] Every setting applied by the restore kit has a documented **why** so the next owner can make informed decisions
- [ ] Hardware-specific settings (GPU params, display scale, ASUS tools, fan control) are gated behind explicit detection or clearly flagged as optional