---
title: "MIR API guide"
status: current
applies_to: "MIR development"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-27
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-api-guide
---

# MIR API guide

## Implemented candidate interface

The [API contract](../spec/api.md) defines one public name, two lifecycle surfaces and a Lua-first SDK. The candidate implements the [data helper](../source/api/v1/data.lua) and [runtime queries](../source/api/v1/runtime.lua). They have exact-source native consumer evidence, but API1.0 stability and MIR5 release acceptance still require the remaining affected client and final-candidate checks. Use the independent examples in disposable test worlds while qualification continues.

A required extension declares a normal dependency on MIR, calls the data helper only after its own references are available, and owns its runtime behavior. An optional extension checks for MIR and its capability before using it; its absent-MIR case must actually load.

Use native fields for science/cost and known technology definitions. Resolve the extension's own settings in its settings/data stages. MIR does not create a setting retroactively from a data registration.

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

The [SDK](../sdk/README.md) links the required alpha and optional late beta test mods. The [F200 native consumer chain](../spec/evidence/api-consumers-f200-chain.json) verifies immediate publication, detached queries, actual200 then202 cables from equal100-plate inputs, save and two cold reloads. That fixture uses native research setters rather than labs. The separate [optional-absence chain](../spec/evidence/api-optional-absence-chain.json) proves native loading without MIR; it is CreateOnly evidence, without save or gameplay coverage. Historical targets and final-candidate clients retain their own capability and qualification obligations.

The [canonical draft3 native chain](../spec/evidence/api-canonical-native-chain.json) records source `554c5af31cc2986e3f0901f68909a447bd4c6304` on exact2.0.77 and2.1.23 with93 verified artifact members. Its two F200 consumers pass actual effects, physical200→202 cable production, save and two unchanged-save cold reloads using native research setters. F210 passes two independently named namespace consumers at native creation; the representative science-ambiguity case also loads and remains explicitly unqualified for the unknown reporter profile. These results exercise the restricted draft3 declaration boundary; they do not establish real joining-client or final-current-package acceptance. Earlier staging and nested-lock controller failures remain preserved separately.

## What an extension can rely on

Immediate data operations in the documented stage; clear duplicate/input errors; bounded read-only runtime query records; detached boundary tables; API version distinct from product version. It cannot rely on MIR to execute after all other mods, arbitrate unknown owners, reconstruct removed save state or sandbox arbitrary Lua.

An extension can use `data:extend()` directly. MIR helpers are optional and should remove meaningful duplication rather than wrap every native operation.

## Before API 1.0 becomes stable

Exercise two independently named extensions in native Factorio, including optional absence, final-fixes ordering, conflicts, mutation isolation, researched output, save/reload and real client loading. Keep unknown/unimplemented capabilities false. Audit genuine previous API/MEP consumers and document their transition; do not promote old preview discovery to trusted execution.

## Draft revision and family creation

The candidate examples follow **MIR API1.0.0-draft.3**. The module path is `__more-infinite-research__.api.v1.data`; the runtime remote interface is `more-infinite-research.api.v1`. These implemented MIR5 surfaces are absent from released MIR4. The product version and API version remain independent.

Data creation is implemented on F200/F210; native qualification remains separate. It accepts only the documented numeric-count technology subset: control-byte-free names, existing prerequisites, distinct science ingredients, time from `1/60` through `3600000` seconds, `character-crafting-speed` effects for ordinary creation, and API-created recipe-productivity effects. F200 science must be an existing `ToolPrototype`; F210 accepts the explicit `ItemPrototype` categories listed in the contract. MIR supplies the packaged thumbnail for every API result. Formula costs, caller assets, localization, triggers, arbitrary native fields and caller productivity effects reject before writes. Use `add_technologies(prototypes)` for an ordered finite family with internal forward references. All local preflight occurs before intended writes; an invalid family does not become a partially accepted pending registration. A later foreign target still requires calling in the proper later data-stage round. See [the API contract](../spec/api.md) and diagram 06 in the [atlas](diagrams/index.html).
