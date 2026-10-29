---
title: "MIR API guide"
status: current
applies_to: "MIR development"
audience: developer
doc_type: reference
owner: mir-maintainers
last_reviewed: 2026-10-29
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-api-guide
---

# MIR API guide

## Implemented candidate interface

The [API contract](../spec/api.md) defines one public name, two lifecycle surfaces and a Lua-first SDK. The candidate implements the [data helper](../source/api/v1/data.lua) and [runtime queries](../source/api/v1/runtime.lua). Two independently installed consumers have named native data, physical/save and current real-client evidence. API1.0 stability still requires the final documented-subset verdict and version freeze; the overall MIR5 release verdict remains separate. Use the independent examples in disposable test worlds while qualification continues.

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

## Current consumer qualification boundary

The [current7b0 production applicability review](../spec/evidence/api-production-current7b0-aero-applicability-r01.json) independently verifies nine portable bodies,91 original custody members and eight actual logs for the original12c F200/F210 Base production/save cases. Seven consumed entrypoint/API/Generator/config/target payloads match each actual current ZIP. The original200/202 cables from equal100-plate batches and two unchanged-save cold reloads per target retain their recorded2.0.77/D3 or2.1.23/SteamFE4 identities; this is no new2DDD or standalone8DC physical run. These fixtures use native research setters, not labs.

The corrected [F200 client case](../spec/evidence/library-f200-native-names-private-native-chain-r01.json) and [F210 Base/Space Age cases](../spec/evidence/library-f210-native-names-private-native-chain-r01.json) now observe both independently installed consumers on1D45/2DDD. Across eighteen actual EN/DE client phases at initial join,rejoin and saved-host restart, each client log contains the Alpha/Beta read-only load-query pair with preserved native API research/effects. Queries run in the first game-available event after load; their on_load callbacks only register the pending local observation. These are current2.0.77/D3 and standalone2.1.23/8DC client observations, separate from the older production experiments. The [F200 optional-absence review](../spec/evidence/api-optional-absence-f200-aero-applicability-r01.json) retains its exact no-MIR CreateOnly result; an inactive MIR archive is not a consumed input.

This covers the named draft3 consumers and tested lifecycle paths. It does not qualify arbitrary third-party methods,overhaul closures or historical target capabilities. The [available-archive consumer audit](../spec/evidence/api-consumer-available-archive-audit-chain.json) retains zero named old-interface/SDK/MEP matches in31 verified archives while preserving the runtime bridges; computed names and external consumers remain unknown. No old externally consumed contract is retired by these results. Before final stabilization, independently review the documented subset,existing boundary-budget controls and capability/version records against the accepted package; no API expansion is required for this release.

## What an extension can rely on

Immediate data operations in the documented stage; clear duplicate/input errors; bounded read-only runtime query records; detached boundary tables; API version distinct from product version. It cannot rely on MIR to execute after all other mods, arbitrate unknown owners, reconstruct removed save state or sandbox arbitrary Lua.

An extension can use `data:extend()` directly. MIR helpers are optional and should remove meaningful duplication rather than wrap every native operation.

## Before API 1.0 becomes stable

Exercise two independently named extensions in native Factorio, including optional absence, final-fixes ordering, conflicts, mutation isolation, researched output, save/reload and real client loading. Keep unknown/unimplemented capabilities false. Audit genuine previous API/MEP consumers and document their transition; do not promote old preview discovery to trusted execution.

## Draft revision and family creation

The candidate examples follow **MIR API1.0.0-draft.3**. The module path is `__more-infinite-research__.api.v1.data`; the runtime remote interface is `more-infinite-research.api.v1`. These implemented MIR5 surfaces are absent from released MIR4. The product version and API version remain independent.

Data creation is implemented on F200/F210; native qualification remains separate. It accepts only the documented numeric-count technology subset: control-byte-free names, existing prerequisites, distinct science ingredients, time from `1/60` through `3600000` seconds, `character-crafting-speed` effects for ordinary creation, and API-created recipe-productivity effects. F200 science must be an existing `ToolPrototype`; F210 accepts the explicit `ItemPrototype` categories listed in the contract. MIR supplies the packaged thumbnail for every API result. Formula costs, caller assets, localization, triggers, arbitrary native fields and caller productivity effects reject before writes. Use `add_technologies(prototypes)` for an ordered finite family with internal forward references. All local preflight occurs before intended writes; an invalid family does not become a partially accepted pending registration. A later foreign target still requires calling in the proper later data-stage round. See [the API contract](../spec/api.md) and diagram 06 in the [atlas](diagrams/index.html).

## Declaration input bounds

The implemented draft3 preflight limits each family to at most64 rows,with at most512 traversed entries across its submitted definitions,table nesting depth16 and4096 bytes per string/key. Named recipe targets are capped at64. These limits apply together:64 is an upper bound,not a promise that64 populated definitions fit the shared512-entry budget. Native Factorio validation still applies after MIR's supported-subset preflight. The [bounded host measurement](../spec/evidence/api-boundary-host-aero-measurement-r01.json) retains100 observations on explicit Lua5.2:the named1/8/16/32-row shapes publish once,larger or malformed shapes reject before writes,and observed rejection work stays bounded as width/depth grows beyond the current caps. Its hook counts exclude engine internals and its host elapsed values include instrumentation;it is no native timing,API-stability or release verdict. No implementation limit is changed by this documentation.
