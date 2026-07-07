---
title: "ADR 0011: Runtime Code Boundaries"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: adr
owner: mir-maintainers
last_reviewed: 2026-07-07
supersedes: []
superseded_by: []
---
# ADR 0011: Runtime Code Boundaries

Status: Accepted for 3.0 planning

Date: 2026-07-07

## Decision

Static productivity streams should not require runtime code. Runtime behavior
must be event-driven, bounded, documented, and validated. Broad `on_tick`
scanning remains forbidden without a future explicit exception.

`control.lua` stays in MIR because the current branch has scripted technology
features that need runtime event handlers. The root file must remain a thin call
to `prototypes/mir/stage/control.lua`. That stage module may register runtime
handlers through `script` and delegate to `prototypes/mir/runtime/` modules, but
it must not inspect `data.raw`, call `data:extend`, or create technology
prototypes.

## Consequences

MIR uses native technology modifiers and prototype-stage behavior first.
Runtime systems remain narrow and conservative. Active runtime implementation
belongs under `prototypes/mir/runtime/`; root `control.lua` is only the Factorio
entrypoint wrapper.
