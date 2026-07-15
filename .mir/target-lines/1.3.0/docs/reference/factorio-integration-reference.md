---
title: "Factorio Integration Reference"
status: current
applies_to: "3.0.0+"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Factorio Integration Reference

Factorio-facing files stay at the mod root or in Factorio-recognized directories:

- `info.json`
- `changelog.txt`
- `settings.lua`
- `data.lua`
- `data-updates.lua`
- `data-final-fixes.lua`
- `control.lua` when runtime code is needed
- `locale/`
- `migrations/`
- `prototypes/`

Repository-only folders such as `docs/`, `fixtures/`, `scripts/`, `.mir/`, and `.codex/` are excluded from shipped release zips.

## Runtime Entrypoint

`control.lua` is runtime-only. Keep it out of MIR unless the branch has runtime responsibilities such as event handlers, commands, remote interfaces, GUI, per-save storage, configuration-change handling, or runtime diagnostics.

MIR's normal compatibility compiler work belongs to the data stage. Prototype discovery, recipe indexing, generated technology construction, and `data.raw` mutation must not move into `control.lua` or `prototypes/mir/runtime/`.

The current branch keeps `control.lua` because scripted technology candidates register runtime events through `prototypes/mir/runtime/scripted_techs.lua`. The root file stays thin and routes through `prototypes/mir/stage/control.lua`.
