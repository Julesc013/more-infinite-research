---
title: "Runtime and Research Library"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-runtime-specification
---

# Runtime and Research Library

`RUN-01` — Native research effects have no recurring MIR Lua work. Scripted effects, cap reconciliation and UI are separate modules with their actual event and state requirements. Disabling a feature prevents unnecessary recurring work after any required restoration of saved contributions.

## Lifecycle and ownership

Use one explicit registration owner per shared event. Independent events need no general dispatcher. A tiny composition function is justified when multiple features otherwise overwrite one another's registration; a universal event bus is not.

Import modules while control code is parsed. Do not `require` within an event, GUI callback or remote call. `on_load` reconnects local references/subscriptions without changing saved state or using unavailable game state. Conditional handlers must reconstruct consistently on a joining client; multiple forces do not test multiplayer. [Libraries](https://lua-api.factorio.com/latest/auxiliary/libraries.html), [LuaBootstrap](https://lua-api.factorio.com/latest/classes/LuaBootstrap.html)

`RUN-02` — Keep the minimum durable state with one owner per field, explicit schema evolution and tested invalid-object cleanup. Derivable immutable data belongs in local caches only when useful. The data-stage state does not persist into runtime. Do not transport the old compiler snapshot for caps or the Library.

A module is lazily activated by feature/settings checks, but a control-stage module needed for future callbacks must still be imported before callbacks. Lazy activation is not permission for prohibited late imports.

## Required feature fidelity

| Feature | Contract |
|---|---|
| Caps | Preserve earned-above-cap effects, queue/current progress and foreign disablement. Reconcile relevant research/force/configuration changes without rescanning the catalogue per event. |
| Spoilage | Preserve the baseline global scope and highest-eligible-force policy where delivered, including ownership of applied multiplier and external-write handling. Do not silently change to per-force behavior. |
| Agriculture | Preserve actual planted-entity lifecycle and rates; deterministic batches cannot change outcomes under load without approval. |
| Passive repair | Periodic work is permitted when necessary. Preserve rate, selection, force/clone/destroy transitions and bounded scheduling. No blanket ban on `on_tick` that deletes the feature. |
| Native effects | Never duplicate a native modifier in Lua or infer ownership from an aggregate field. |
| Historical carriers | Keep real migration-state identities/semantics until their removal is qualified. Do not expose hidden credit as ordinary research. |

`RUN-03` — A last-applied-value check does not fully identify independent foreign writers. Preserve existing documented behavior and identify ambiguous shared-modifier cases; do not claim perfect ownership or reconstruct arbitrary third-party offsets from MIR levels.

## Library

`RUN-04` — Stable replacement scope retains delivered search, filters, details, settings/cap explanation, native research navigation, personal focus/scroll/query and translations. It uses a compact identity catalogue plus actual force/prototype state, never the Generator or reconstructed compilation proofs.

Build only the visible/required view; search is allowed to inspect the necessary names/text linearly. Translation/search caches have clear locale/force/configuration lifetimes and bounded sizes. Discard stale callbacks by generation token. Revalidate on open and actual events; do not run a hidden continuous whole-catalogue refresh merely to keep closed UI current.

Native research is authoritative. Do not implement a second research queue or a UI selection path that overrides lab/engine selection. Separate global/force/player observations. User-language changes must not mutate gameplay state.

Two real clients with different views/languages must join, rejoin and reconnect after a host save/restart. Measure first open, search, refresh and reopen. A lower menu time with a new first-open stall is a failed optimization.

## API and diagnostics

Read-only remote functions must not initialize/repair storage or silently run missing migrations. Return exact native meanings or unavailable data. Observability is bounded: concise reason counts and an explicit support export when requested; no permanent per-event logs or profiler. Deterministic gameplay budgets use ticks/work counts, not wall-clock time.

## Deterministic execution and saved-state restoration

`RUN-05` — Apply [determinism](determinism.md), especially fixed tick/work scheduling, reconstruction of conditional handlers, presentation isolation and reproducible state transitions. Runtime must not import the Generator. Do not use machine-time budgets to choose which entities receive an effect. Cleanup on disable is explicit one-time work; steady-state inactivity is measured after it.

Runtime API queries needing native game objects are not callable during control parsing or `on_load`. Register functions while parsing, call them only in documented game-available callbacks. An API consumer owns its own handlers and storage. Registered callable methods do not imply a per-tick MIR loop.
