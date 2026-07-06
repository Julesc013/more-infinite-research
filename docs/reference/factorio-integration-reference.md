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

Factorio-facing files stay at the mod root or in Factorio-recognized
directories:

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

Repository-only folders such as `docs/`, `fixtures/`, `scripts/`, `.mir/`, and
`.codex/` are excluded from shipped release zips.
