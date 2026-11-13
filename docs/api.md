---
title: "MIR API guide"
status: current
applies_to: "MIR development"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-11-11
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-api-guide
---

# MIR API guide

## Start here

MIR 5 betas include the **MIR API 1.0.0** documented subset. Use the [data helper](../source/api/v1/data.lua) to create supported research during the data stage and the [runtime interface](../source/api/v1/runtime.lua) to read native research state. The [API contract](../spec/api.md) defines the exact fields, errors and capability limits. Whole-product stable acceptance remains open.

| Task | Interface |
|---|---|
| Check version or available operations | `get_version()` and `get_capabilities()` on either surface |
| Create one supported technology | Data: `add_technology(prototype)` |
| Create an ordered family, including local forward references | Data: `add_technologies(prototypes)` |
| Add named recipe-productivity effects | Data: `add_productivity(prototype, recipe_names, change)` |
| Read one force's technology | Runtime: `get_research(force_index, technology_name)` through `remote.call` |

The data module is `__more-infinite-research__.api.v1.data`; the runtime remote interface is `more-infinite-research.api.v1`. These MIR 5 surfaces are absent from released MIR 4. Check the API major before using it. The returned `product` is the selected edition's distribution version, such as `5.0.21006`; it is separate from API version `1.0` and source release `5.0.6`.

## Create research

A required extension declares a normal dependency on MIR. An optional extension checks `mods["more-infinite-research"]` before requiring the helper and provides an absent-MIR path. Call after the extension's references are available: data operations publish immediately in the caller's stage. MIR does not wait for a later finalizer.

Resolve the extension's own settings in its settings/data stages. MIR cannot create a setting retroactively from a data call. Native `data:extend()` remains available; use MIR helpers where their supported operations remove useful duplication.

```lua
local api = require("__more-infinite-research__.api.v1.data")
local version = api.get_version()
assert(version.major == 1, "This extension needs MIR API 1")
assert(api.get_capabilities().recipe_productivity,
  "This target does not provide recipe productivity")

-- Illustrative external research, NOT a historical MIR identity.
api.add_productivity({
  type = "technology",
  name = "mir-api-example-gear-productivity-1",
  prerequisites = {"automation"},
  unit = {
    count = 100,
    ingredients = {{"automation-science-pack", 1}},
    time = 30
  }
}, {"iron-gear-wheel"}, 0.01)
```

The [SDK](../sdk/README.md) provides independent required-dependency and optional late-stage examples. Each extension owns its event handlers, settings, storage and references.

## Read research at runtime

An optional runtime caller checks `script.active_mods["more-infinite-research"]` and the remote interface. The data-stage `mods` global is unavailable at runtime. Call queries in a game-available handler; `on_load` may register a later observation but must not query game state.

`get_research(force_index, technology_name)` returns a detached native-status table or `nil, error_code`. It reads the named technology without initializing MIR storage or changing research. Its `level` is Factorio's current native level: finite, staged and infinite research do not share a universal completed-count formula. Saved progress is optional where the engine cannot expose it.

From MIR 5.0.12, ordinary default worker cargo research on Factorio 2.0 and 2.1 advances in `mir-worker-storage-default-4`. Query that literal native identity for the default owner. `worker-robots-storage-4` remains a separate first prerequisite or foreign finite stage; it is not an alias for the owner and does not report a combined total level. Consumers must check the actual native technology for the active route; `get_research` retains its existing literal-name semantics.

Version, capability and research result tables are detached snapshots. Use capabilities for the selected target and current context; they do not certify an arbitrary mod combination. The [runtime contract](../spec/api.md#types-and-errors) describes status fields and distinct unavailable/invalid-input errors.

## Supported declarations and bounds

Creation is qualified for the documented subset on Factorio 2.0.77 and 2.1.23. Use native names, optional existing or same-family prerequisite references, a positive integer count, distinct science ingredients and time from `1/60` through `3600000` seconds. Ordinary creation accepts the bounded `character-crafting-speed` effect; `add_productivity` builds its own recipe-productivity effects. MIR supplies the packaged thumbnail.

Factorio 2.0 science inputs must name existing `ToolPrototype`s. Factorio 2.1 also accepts the explicit `ItemPrototype` categories in the contract. Formula costs, caller assets/localization/triggers, arbitrary native fields and caller-supplied productivity effects are rejected before intended writes. A family receives complete local preflight before publication; later foreign references need a call in a suitable later data-stage round.

The combined limits are **64 family rows, 512 traversed definition entries, nesting depth 16, 4096 bytes per string/key and 64 recipe targets**. All apply together: a populated 64-row family may exceed the entry budget. Native Factorio validation still applies. The [host boundary measurement](../spec/evidence/api-boundary-host-aero-measurement-r01.json) checks bounded admission work; it does not measure native game speed or change these limits.

## Tested scope and remaining limits

The [scoped API 1.0 decision](../spec/evidence/api1-documented-subset-qualification-r01.json) retains exact source, package, engine and fixture identities. It combines the following observations without turning them into new runs of a later package.

| Area | Recorded evidence and limits |
|---|---|
| Declaration admission, publication and queries | Named [Factorio 2.0](../spec/evidence/api-boundary-f200-native-chain-r01.json) and [Factorio 2.1](../spec/evidence/api-boundary-f210-native-chain-r01.json) cases cover the restricted declaration and native-query boundary. |
| Useful effects and save/reload | [Two independent consumers](../spec/evidence/api-physical-modern-native-chain-r01.json) produce 200 then 202 cables from equal 100-plate inputs and pass two cold reloads per case. These fixtures use native research setters; they do not demonstrate lab-earned research. The recorded outer-runner failure remains separate. |
| Joining clients | Recorded [Factorio 2.0](../spec/evidence/library-f200-native-names-private-native-chain-r01.json) and [Factorio 2.1 Base/Space Age](../spec/evidence/library-f210-native-names-private-native-chain-r01.json) cases observe read-only consumer queries at initial join, rejoin and saved-host restart in English/German. They do not establish every Library interaction. |
| Optional absence | Original [Factorio 2.0](../spec/evidence/api-optional-absence-f200-aero-applicability-r01.json) and [Factorio 2.1](../spec/evidence/api-optional-absence-f210-aero-applicability-r01.json) cases verify guarded loading without MIR. These are load-only results; the latter retains its source/profile limits. |

The [consumer audit](../spec/evidence/api-consumer-available-archive-audit-chain.json) covers the inspected archives; computed names and outside consumers remain unknown. Existing runtime bridges remain preserved. The [documented-subset matrix](../spec/evidence/api-documented-subset-matrix-aero-r01.json) separates native observations, host controls and unresolved cases.

MIR 5 is available as a GitHub beta. Stable product qualification, affected save/client state and the legacy Settings-search interaction remain separate work. Review changed consumed inputs before reusing old evidence. Unknown historical capabilities, arbitrary third-party methods and untested overhaul combinations remain outside the linked qualification; foreign-interface collision currently has host controls only.
