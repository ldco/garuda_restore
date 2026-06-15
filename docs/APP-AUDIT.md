# Application Audit & Rationale

> Date: 2026-06-14

---

## Removed

| Package | Category | Reason |
|---------|----------|--------|
| `trae-bin` | IDE | ByteDance IDE — redundant with VS Code + Cursor |
| `kelvpn` | VPN | Redundant — 7 other VPN tools available |
| `wps-office` + fonts + mime | Office | Chinese office suite — LibreOffice covers all needs |
| `onlyoffice-bin` | Office | Redundant — LibreOffice is the single office suite |
| `apostrophe` | Markdown | Presentation tool, not a proper MD reader — replaced by ghostwriter |
| `apidog-bin` | API testing | Proprietary GUI, heavy — replaced by xh (CLI) + Bruno (GUI if needed) |
| `snapd` | Package manager | Installed daemon, ZERO snaps — dead weight |

---

## Added / Replaced

| Tool | Category | Replaces | Why |
|------|----------|----------|-----|
| `xh` | HTTP client | Apidog | Terminal-native, Rust-based, instant, scriptable, 1.4 MB |
| `bruno` | API GUI | Apidog | Open-source, collections as text files (git-friendly), local-first |

---

## Evaluation — Why One Over Another

### Office: LibreOffice vs WPS vs OnlyOffice

| Criterion | LibreOffice | WPS Office | OnlyOffice |
|-----------|-------------|------------|------------|
| License | MPL 2.0 | Proprietary (Chinese) | AGPL 3.0 |
| Format fidelity | Excellent | Good | Better with MS formats |
| KDE integration | ✅ Qt-native | ❌ Mixed | ❌ GTK/Electron |
| Package size | 350 MB | 900 MB | 500 MB |

**Verdict: LibreOffice** — Qt-native on KDE, fully open-source, single suite to maintain.

### Markdown: Apostrophe vs Ghostwriter vs Marktext

| Criterion | Apostrophe | Ghostwriter | Marktext |
|-----------|------------|-------------|----------|
| Type | Presentation tool | Distraction-free editor | WYSIWYG editor |
| KDE integration | ❌ Libadwaita/GNOME | ✅ Qt/KDE-native | ❌ Electron |
| WYSIWYG | ❌ | ✅ Preview pane | ✅ Live preview |
| Resource usage | Low | Very low | ~200 MB RAM |

**Verdict: ghostwriter** — already installed, KDE-native, zero overhead. Marktext available if WYSIWYG needed.

### API Testing: Apidog vs xh+Bruno

| Criterion | Apidog | xh | Bruno |
|-----------|--------|----|-------|
| Type | Full API IDE | CLI HTTP client | GUI collections |
| Install size | 300 MB | 1.4 MB | 150 MB |
| Open source | ❌ | ✅ MIT | ✅ MIT |
| Git-friendly | ❌ Database | ✅ Pipeable | ✅ Text files |
| Scriptable | JS in GUI | ✅ Shell pipes | ✅ JS in GUI |
| Offline | ✅ | ✅ | ✅ |

**Verdict: xh + Bruno** — xh for quick terminal requests, Bruno if GUI collections needed. Both open-source, git-friendly, no accounts.

---

## Current State — By Category

### Development
| Tool | Verdict |
|------|---------|
| VS Code | ✅ Primary IDE |
| Cursor | ✅ AI IDE |
| OpenIDE | ⚠️ 3rd IDE — evaluate if still used |
| Android Studio | ✅ Mobile dev |
| Docker + Compose | ✅ |
| GitHub CLI + lazygit | ✅ |
| npm + pnpm | ✅ |

### Browsers (4 — consider reducing to 2)
| Browser | Usage |
|---------|-------|
| Brave | ✅ Daily driver |
| Firefox | ✅ Backup / privacy |
| Chromium | ⚠️ Only used by Puppeteer MCP — could auto-install |
| carbonyl-bin | ❌ Terminal browser — ever used? |

### Messengers (5 — consider reducing)
| App | Verdict |
|-----|---------|
| Telegram | ✅ Daily driver |
| Signal | ✅ Backup secure messenger |
| Discord | ⚠️ Only if active in communities |
| Zoom | ⚠️ Only if clients require it |
| Wire | ❌ Messenger + VPN — redundant |

### VPN/Proxy (8 — very high)
| Tool | Purpose |
|------|---------|
| happ-desktop-bin | ✅ Daily VPN + tunnel |
| hiddify-next-bin | Multi-protocol proxy |
| prizrak-box-bin | VPN/proxy |
| v2raya | V2Ray manager |
| xray-bin | Xray core (dependency of v2raya) |
| ypn-client | VPN client |
| + kelvpn (removed) | |

8 VPN tools is excessive. If Happ covers all needs, hiddify/prizrak/ypn can be removed.

### Creative Suite
| Tool | Purpose |
|------|---------|
| DaVinci Resolve | Professional video editing |
| Kdenlive | Quick video edits |
| OBS Studio | Screen recording |
| Blender | 3D modeling |
| Ardour | Audio production |
| Audacity | Quick audio edits |
| GIMP + Inkscape + Krita | Image editing & design |
| Darktable + Digikam | Photo management |

### Office
| Tool | Verdict |
|------|---------|
| LibreOffice | ✅ Single office suite |

### API Testing
| Tool | Verdict |
|------|---------|
| xh | ✅ Terminal HTTP client (1.4 MB, Rust, instant) |
| curl + jq | ✅ Already present, universal |
| Bruno | ✅ Installed — offline-first collections, git-friendly |
| Apidog | ❌ Removed — going commercial, replaced by xh+Bruno |

**Rationale:** Apidog is a full API IDE with cloud dependency (mock servers, docs gen, team sharing). xh covers 90% of daily needs (quick HTTP requests). Bruno covers the GUI/collections gap when needed. Both are free, open-source, git-friendly, no accounts.

### Database
| Tool | Verdict |
|------|---------|
| Beekeeper Studio Free | ✅ Chosen — modern UI, SQLite+PG+MySQL+SQL Server free |
| DBeaver | ❌ Rejected — dated Java UI |
| DbGate | ❌ Not needed — Beekeeper free covers everything |

**Rationale:** Beekeeper Community (free) covers all SQL databases needed (SQLite, PostgreSQL). NoSQL (MongoDB, Redis) Pro features not needed — covered by Docker + CLI tools. SSH tunnels, CSV import, backup/restore all covered by existing tools (`ssh`, LibreOffice, `pg_dump`/`sqlite3`). No Pro purchase needed.

```bash
paru -S beekeeper-studio-bin
```

---

## Recommended Next Removals

```bash
# Evaluate if still needed:
paru -R carbonyl-bin            # terminal browser — ever used?
paru -R wire-desktop            # messenger+VPN — Telegram+Happ covers
paru -R hiddify-next-bin        # if Happ covers VPN needs
paru -R prizrak-box-bin         # if Happ covers VPN needs
paru -R ypn-client              # if Happ covers VPN needs
paru -R openide-bin             # if VS Code + Cursor is enough
```
