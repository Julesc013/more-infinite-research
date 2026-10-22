---
title: "MIR architecture"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-architecture-specification
---

# MIR architecture

## Decision

Use direct Factorio definitions with a small Generator. Remove general research discovery, factory-acquisition proof, whole-world snapshots, generic transformation plans and routine identity/serialization chains from player execution. Preserve the product contract rather than every old internal representation.

`ARCH-01` — Production research MUST come from authored identities, explicit progression and approved effect/binding rules. Selecting recipes for an existing authored family is not permission to invent new families or science progression.

`ARCH-02` — Keep four independent execution paths: research construction, optional prototype overrides, necessary scripted effects, and Library presentation. The API is a thin boundary around useful operations, not a mandatory fifth pipeline. Runtime and migrations MUST NOT import the Generator.

`ARCH-03` — The canonical player root is `source/`; packaging selects its one active implementation during transition. Production modules MUST NOT import tests, developer SDK, evidence, subprocesses, network services or the retired implementation. No player-side preprocessing, custom binary research format, required artifact cache, fallback compiler, class hierarchy or general intermediate representation.

`ARCH-04` — Native Factorio behavior is preferred where it preserves semantics. The engine computes native research effects and formulas. Native bonuses MUST NOT be reapplied by Lua. Existing scripted behavior is not silently deleted because it is harder to simplify.

## Final responsibility layout

```text
source/
  settings.lua
  data.lua
  data-final-fixes.lua
  control.lua
  research/
    generator.lua
    settings.lua
    identity.lua
    productivity.lua
    bonuses.lua
    continuations.lua
  compatibility/
    dispatch.lua
    bindings.lua
    <actual_integration>.lua
  overrides/
    productivity.lua
    modules.lua
    recycling.lua
  runtime/
    events.lua
    caps.lua
    spoilage.lua
    agriculture.lua
    repair.lua
    library.lua
  api/v1/
    data.lua
    runtime.lua
  migrations/
  locale/
  graphics/
targets/
spec/
docs/
sdk/
tests/
tools/
```

This is a responsibility map, not a scaffolding order. Create a file only when it contains real work. Keep cohesive declarations together rather than one file per trivial technology. An empty data-updates entrypoint is unnecessary; add it only for a demonstrated load-order contract. `identity.lua` contains compact IDs/setting metadata shared between stages, not emitted prototype copies or a second catalogue language.

`ARCH-05` — Source is ordinary Lua. Native prototype tables are the only production construction representation. Small JSON inventories are developer records, not game inputs. One target adapter supplies real shape/API differences; do not duplicate the complete product per engine.

## Boundaries and activation

`research/` may use small identity/settings/target helpers and native prototypes. Compatibility selects a variant and passes exact names/values to the Generator. The Generator MUST NOT contain Bob/Angel/K2/SE-specific policy. Overrides own broad prototype property changes. Runtime owns persistent contributions and lifecycle; Library owns view state, not research semantics.

`ARCH-06` — Check an absent integration or inactive override before importing its body or enumerating prototypes. A small dispatch table is not free, but an absent mod must not construct its mapping tables or run analysis. Disabling a feature with an already-applied saved contribution may still require one explicit cleanup/reconciliation; it is not an excuse for ongoing polling.

`ARCH-07` — Each mutable table has a clear owner. Construct nested output arrays once; do not alias shared mutable templates or a caller's arrays into emitted prototypes. Copy only the necessary boundary data. Internal ownership conventions are checked with opposing tests, not runtime proxy/certificate frameworks. Never mutate foreign fields outside the explicit patch scope.

`ARCH-08` — Native research has no recurring MIR tick work. Necessary runtime scheduling is deterministic by tick/work count, never machine wall time. Shared event registration is explicit and only as centralized as needed to prevent handler replacement.

## Failure and safety model

Expected optional absence may omit a new contribution with a reason. Required historical identities, unexpected duplicate owners, malformed definitions and unsupported migrations are not ordinary optional absence. Follow [compatibility](compatibility.md) and [migration](migrations.md) rules. Do not blanket-catch startup errors and continue after partial mutation.

Local validation is not a sandbox: data-stage mods share prototype access and can change results after MIR. API code cannot prevent arbitrary other Lua code from bypassing it. Define tested profiles and failure boundaries, not universal crash-freedom.

## Complexity and maintainability

`ARCH-09` — No per-family whole-recipe scan, repeated world graph construction, fixed-point research generation or generic serialized mutation journal. A declared parity requirement can justify one bounded collector outside the Generator or one relevant graph check; it requires a named consumer, work-bound test and native evidence. Do not remove useful broad behavior to obtain a cleaner complexity slogan.

`ARCH-10` — A new ordinary family should change its declaration and focused test; a new integration should change its adapter, one activation entry and relevant tests/docs. Changes to many infrastructure authorities require design review before proceeding.

Readable compact code is preferred over compressed code. Core LOC/import growth, output size and tooling latency are review signals, not numerical substitutes for maintainability. No dependency-injection container, universal event bus, plugin registry or schema platform without a demonstrated consumer that cannot be served directly.

## References

Engine stage constraints: [Factorio lifecycle](https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html). Package conventions: [Factorio mod structure](https://lua-api.factorio.com/latest/auxiliary/mod-structure.html). The inherited pack recorded a 2.1.14 documentation observation. Reverification on 2026-10-22 found the official latest lifecycle/libraries/migrations/remote pages identifying themselves as 2.1.23. This is documentation verification, not native execution. Exact-version URL fetches were unavailable during this revision; preserve the observed version and check each actual implementation target.

## Determinism is a cross-cutting contract

`ARCH-11` — Apply [Determinism](determinism.md) across build, settings, Generator, runtime and migration boundaries. Same complete inputs give equal semantic outputs; hardware timing is not part of that promise. Ordering/ownership must be specified rather than inferred from traversal order. No data-stage Lua state is assumed to persist into gameplay.

The visual atlas is explanatory, not an alternate authority. Its graphs are generated from one developer-only diagram catalogue; no diagram, inventory or SDK file is loaded by Factorio.
