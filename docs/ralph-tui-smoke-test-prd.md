# Plan: Ralph TUI Smoke Test — Note Saver PRD

## Goal
Validate that Ralph TUI (`ralph-tui`) works end-to-end by running it against a minimal, well-defined PRD and verifying it produces a working CLI application.

## What This Tests
- Ralph TUI can parse `prd.json` with `userStories`, `dependsOn`, and `acceptanceCriteria`
- The Kilo agent plugin (via `kilo-ralph` wrapper) receives and executes user stories
- Dependency ordering is respected (US-001 → US-002 → US-003 → US-004)
- Progress tracking in `.ralph-tui/progress.md` is updated per iteration
- Completion signals (`<promise>COMPLETE</promise>`) are detected

## PRD: Note Saver CLI

| Property | Value |
|----------|-------|
| File | `prd.json` (project root) |
| Schema field | `userStories` (NOT `tasks`) |
| Story count | 4 |
| Technology | Node.js, zero dependencies |
| Output artifact | `note-saver/index.js` (single-file CLI) |

### Schema Fix Applied

The `kilo-prd` wrapper generates `tasks` field, but the actual Ralph TUI JSON tracker expects:
- `name` (project name)
- `branchName` (optional git branch)
- `userStories[]` with: `id`, `title`, `description`, `acceptanceCriteria`, `priority` (number), `passes` (boolean), `dependsOn`

### Story Dependency Graph

```
US-001 (scaffold, pri=1)
    │
    ▼
US-002 (save logic, pri=1)
    │
    ▼
US-003 (read logic, pri=2)
    │
    ▼
US-004 (CLI wiring, pri=1)
```

### Story Summary

| ID | Title | Dependencies | Expected Output |
|----|-------|-------------|-----------------|
| US-001 | Scaffold project structure | none | `note-saver/` with package.json, README.md, .gitignore |
| US-002 | Implement note saving logic | US-001 | `saveNote()` function in index.js |
| US-003 | Implement note reading logic | US-002 | `readNotes()` function in index.js |
| US-004 | Wire CLI argument parsing | US-003 | Executable script with `save`/`read` commands |

## Verification Checklist

- [ ] `ralph-tui run --prd ./prd.json` starts without schema errors
- [ ] All 4 user stories complete (check `.ralph-tui/progress.md`)
- [ ] `note-saver/index.js` exists and is executable
- [ ] `node note-saver/index.js save "test message"` succeeds
- [ ] `node note-saver/index.js read` shows saved note
- [ ] Running `node note-saver/index.js` with no args prints usage help
- [ ] `.ralph-tui/progress.md` documents each story with learnings

## Ralph TUI Command

```bash
cd /run/media/ldco/3734114f-7123-41f5-8f63-7f43c94879eb/LinuxDCO/garuda-restore
ralph-tui run --prd ./prd.json
```

## Expected Failure Modes

| Symptom | Likely Cause |
|---------|-------------|
| "Invalid prd.json schema" | Field names wrong: must be `userStories` not `tasks`, `acceptanceCriteria` not `acceptance_criteria` |
| Stories run out of order | Dependency resolution bug in tracker |
| Story marked complete but nothing changed | Kilo agent hallucinated completion |
| Same story repeats infinitely | `<promise>COMPLETE</promise>` not detected |

## Rollback
```bash
rm -rf note-saver/ notes.json .ralph-tui/progress.md
```
