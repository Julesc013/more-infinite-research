---
title: "ADR 0013: Factorio Shell And MIR Compiler Namespace"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0013: Factorio Shell And MIR Compiler Namespace

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Context

Factorio loads a small set of root entrypoint files and recognized folders.
MIR's 3.0 compatibility compiler needs stronger boundaries than the current
historical layout can express: root files should be Factorio shell files,
compiler logic should live under one MIR namespace, and development-only
surfaces should stay out of the shipped archive.

## Decision

Use a three-part structure:

```text
Factorio shell:
  info.json, changelog, settings*.lua, data*.lua, control.lua if needed,
  locale/, migrations/, graphics/, prototypes/

MIR compiler namespace:
  prototypes/mir/stage/
  prototypes/mir/core/
  prototypes/mir/platform/
  prototypes/mir/domain/
  prototypes/mir/index/
  prototypes/mir/graph/
  prototypes/mir/classify/
  prototypes/mir/policy/
  prototypes/mir/capabilities/
  prototypes/mir/planner/
  prototypes/mir/emit/
  prototypes/mir/report/
  prototypes/mir/compatibility/
  prototypes/mir/legacy/

Development workspace:
  docs/, fixtures/, scripts/, tests/, build/, dist/, todo.md, CONTRIBUTING.md
```

Root entrypoints should become thin stage wrappers. Compatibility packs register
policy overlays only. `emit/` is the only layer that mutates prototypes. Legacy
paths become shims during the migration so target-line backports can still
cherry-pick small fixes.

## Consequences

- Shipped Lua has one obvious namespace.
- Factorio-specific access is isolated in `platform/`.
- Pure compiler modules become easier to test.
- The package boundary stays clean.
- Backports can preserve old require paths while `dev` moves forward.
- Static validation can enforce dependency direction instead of relying on
  convention.
