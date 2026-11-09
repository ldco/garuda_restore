# PACKAGE MAP

`packages/arch-to-fedora.tsv` has four tab-separated columns:

```
arch_pkg	fedora_pkg	mode	note
```

| mode | meaning |
|---|---|
| `native` | `dnf install fedora_pkg`; on failure the script searches for a best match and records `ALT` |
| `flatpak` | `flatpak install flathub <app-id>` |
| `manual` | not installed; printed at the end and written to the report |
| `drop` | intentionally not carried over |

`packages/excluded.tsv` lists Arch/system packages that must never be mapped
(`filesystem`, `pacman*`, `base*`, `linux-zen*`, `garuda-*`, …). `fedora-native.txt`
is the base package list used by the netinstall `%packages` and the `base` stage.
`flatpak.txt` lists the Flathub IDs.

## Report

Each run writes `packages/report-<timestamp>.tsv`:

```
arch	fedora	mode	status	note
visual-studio-code-bin	code	manual	MANUAL	Microsoft repo
brave-bin	com.brave.Browser	flatpak	FLATPAK
discord	discord	native	OK
```

Statuses: `OK`, `ALT`, `FLATPAK`, `MANUAL`, `FAIL`. The stage fails only with
`--strict-apps` when at least one row is `FAIL`. `verify` reads the newest
report and requires zero `FAIL` rows.

## Adding an entry

1. Add a row (real tabs) with the Arch name and the Fedora/flatpak target.
2. Prefer `native`; use `flatpak` only for well-known Flathub IDs.
3. If unsure, use `manual` with a note — the runtime resolver also tries
   `dnf search` for `native` rows.
4. Re-run: `sudo /root/FedoraKDE/scripts/apps.sh` (idempotent).

## Why not a static one-to-one list

Package names rot between Fedora releases and third-party repos move (asusctl
moved to Terra, supergfxctl is being retired). The map carries intent; the
runtime resolver carries the truth and records every deviation in the report.
