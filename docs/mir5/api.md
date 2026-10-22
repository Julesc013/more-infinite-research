---
title: "MIR API guide"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: guide
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-api-guide
---

# MIR API guide

## Candidate interface, not an available release claim

The [API contract](../../spec/mir5/api.md) proposes one public name, two lifecycle surfaces and a Lua-first SDK. This archive contains consumer examples, not the MIR implementation. Do not install them into a valuable save or present their syntax as a verified released interface.

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
  icon = "__base__/graphics/technology/automation.png",
  icon_size = 256,
  prerequisites = {"automation"},
  unit = {
    count_formula = "100 * 2^(L-1)",
    ingredients = {{"automation-science-pack", 1}},
    time = 30
  },
  max_level = "infinite",
  upgrade = true
}, {"iron-gear-wheel"}, 0.01)
```

The required and optional test-only examples are under [SDK](../../sdk/mir5/README.md). They use only the proposed public surface. Native test status is **not run**; exact historical engines need their own capability metadata and API contracts.

## What an extension can rely on

Immediate data operations in the documented stage; clear duplicate/input errors; bounded read-only runtime query records; detached boundary tables; API version distinct from product version. It cannot rely on MIR to execute after all other mods, arbitrate unknown owners, reconstruct removed save state or sandbox arbitrary Lua.

An extension can use `data:extend()` directly. MIR helpers are optional and should remove meaningful duplication rather than wrap every native operation.

## Before API 1.0 becomes stable

Exercise two independently named extensions in native Factorio, including optional absence, final-fixes ordering, conflicts, mutation isolation, researched output, save/reload and real client loading. Keep unknown/unimplemented capabilities false. Audit genuine previous API/MEP consumers and document their transition; do not promote old preview discovery to trusted execution.

## Draft revision and family creation

This pack aligns every example with **MIR API 1.0.0-draft.2**. The module path is `__more-infinite-research__.api.v1.data`; the runtime remote interface is `more-infinite-research.api.v1`. These are proposed interfaces, not present in the released MIR 4 player mod.

Use `add_technologies(prototypes)` for an ordered finite family with internal forward references. All local preflight occurs before intended writes; an invalid family does not become a partially accepted pending registration. A later foreign target still requires calling in the proper later data-stage round. See [the API contract](../../spec/mir5/api.md) and diagram 06 in the [atlas](diagrams/index.html).
