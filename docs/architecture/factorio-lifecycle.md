---
title: "Factorio Lifecycle Boundaries"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---

# Factorio Lifecycle Boundaries

MIR 3 separates settings-stage UI policy, prototype-stage generation, and
runtime behavior. The stage boundary is a correctness rule, not a folder naming
preference.

## Settings Stage

Factorio loads `settings.lua`, `settings-updates.lua`, and
`settings-final-fixes.lua` before normal prototypes are available. This stage
creates setting prototypes and then applies saved user values.

MIR settings code may use:

- static stream metadata;
- the active `mods` table;
- branch/package policy recorded in `.mir/settings.yml`.

MIR settings code must not use:

- `data.raw`;
- recipe, item, fluid, entity, lab, or technology prototype facts;
- generation diagnostics from `data-final-fixes.lua`.

This is why hidden technology settings are based on `ui_visibility` provider
metadata, not final recipe or technology existence.

## Prototype Stage

`data.lua`, `data-updates.lua`, and `data-final-fixes.lua` run after setting
prototypes are registered. Startup setting values are readable here, and final
prototype facts become progressively more complete.

MIR generation belongs here. The data-final-fixes pipeline must still prove that
targets exist, labs can research the selected science packs, recipe productivity
is safe, ownership policy allows emission, loop risk is acceptable, and the
stream has a stable manifest row. A visible and enabled setting is not enough to
generate a technology.

## Runtime Stage

`control.lua` is runtime save/session behavior. It may register event handlers,
commands, remote interfaces, and per-save storage behavior. It must not inspect
`data.raw`, create technology prototypes, or repair prototype generation after a
save starts.

MIR should omit `control.lua` unless runtime behavior is required. If it exists,
it stays a thin wrapper into `prototypes/mir/stage/control.lua` and runtime
modules under `control/`.

## Hidden Settings

Hidden startup settings remain registered. MIR uses this for unavailable stream
controls so settings files, saves, and backport lanes keep stable IDs.

For normal unavailable technologies:

```lua
hidden = true
```

Do not add:

```lua
forced_value = false
```

Forcing a hidden value can discard the user's intended setting when the provider
mod is enabled again. Reserve `forced_value` for documented safety or migration
cases only.
