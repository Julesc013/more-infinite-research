---
title: "MIR API and SDK"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-api-specification
---

# MIR API and SDK

## Identity and maturity

`API-01` — **MIR API** is the sole current public integration name. The former MEP document at the inspected baseline described a data-only, read-only developer preview whose discovery did not authorize player emission. It is therefore not semantically identical to this interface. Unify naming and responsibility; do not reinterpret old envelopes as executable contributions or merely rename their wire keys.

Before retiring a real externally consumed old contract, record its consumers, preserved fields, explicit converter/adapter or documented major-version transition. Unconsumed previews retain their history and unresolved status without their platform being copied into the player mod. No new parallel `mep/` subsystem.

This file specifies **MIR API 1.0.0-draft.2**, not a released API. The new native interface uses `api/v1/` and `more-infinite-research.api.v1`; this major-version boundary is independent of the product staging directory. It does not reuse the old `MIR4ApiResponseV1` wire contract. The supplied earlier pack's unversioned candidate paths are superseded before implementation; no deployed consumer compatibility is asserted. Product `5.0.0`, API `1.0`, target engine and SDK versions are distinct. Additive compatible capability changes can increment an API minor; changed meaning/removal requires a major transition. Preserve existing externally consumed identifiers where their audit establishes an obligation.

## Two surfaces, native settings

| Surface | Mechanism | Allowed time |
|---|---|---|
| Settings | The extension's native setting prototypes | Its settings-stage files, before settings are finalized |
| Data | `require("__more-infinite-research__.api.v1.data")` | The extension's suitable data-stage round |
| Runtime | `remote.call("more-infinite-research.api.v1", function_name, ...)` | Documented callbacks where required game state is available |

An extension that unconditionally requires MIR must declare a required Factorio dependency. An optional dependency needs an actual `mods[...]` guard and an explicit absent-MIR behavior. Dependencies determine ordering; MIR's final-fixes file is not globally last.

`API-02` — Data calls execute their declared operation **immediately in the caller's stage**. No central contribution queue waiting for a MIR finalizer that may already have run. Forward references needed by a batch must have an explicit local contract; ordinary callers invoke the helper after its dependencies exist. Later mods may still mutate the result.

Use fully qualified internal imports for modules reachable from external callers where needed, and test loading from two differently named extension mods. Do not assume one private registry instance or a shared mutable module cache across callers makes registration reliable.

## Minimal candidate surface

| Function | Signature and result | Status |
|---|---|---|
| `get_version` | `() -> {major=1, minor=0, product=string}` | Data and runtime |
| `get_capabilities` | `() -> {capability_name=boolean, ...}` | Data and runtime; small detached table |
| `add_technology` | `(prototype) -> technology_name` | Data; native-shaped declaration, immediate creation |
| `add_technologies` | `(prototypes) -> technology_names` | Data; ordered finite family, complete local preflight, immediate publication |
| `add_productivity` | `(prototype, recipe_names, change) -> technology_name` | Data; native unit/prerequisite/icon fields; append named recipe-productivity effects |
| `get_research` | `(force_index, technology_name) -> status or nil, error_code` | Runtime; read-only, no whole-catalogue traversal |

Capabilities describe implemented target operations, not claimed modpack compatibility. Do not return `true` because a test was planned. API 1.0 is not frozen until two independently installable consumer mods pass on applicable targets, including late data-stage use and optional absence.

`add_productivity` takes a native technology prototype containing all normal fields and any explicitly intended pre-existing effects, a dense ordered list of distinct recipe names, and a finite per-level native `change`. It rejects duplicate matching effect identities rather than double-adding them. Its supported engine/effect range is advertised; it does not emulate unavailable native productivity on old targets. The extension resolves its own settings before the call. Both inputs and returned queries are isolated from internal mutable state.

`add_technology` performs local shape/identity/reference checks relevant to this operation and delegates final native schema validation to Factorio. It is not a complete reimplementation of the engine schema. Exact native fields remain native; unknown new native fields are not translated into a homemade DSL. API documentation must identify which fields the helper copies/checks and its supported target ranges before public stability.

## Deliberately not part of the initial general API

No universal `extend_technology(name, arbitrary_changes)` patch language, ownership-arbitration registry, arbitrary event callback host, factory scanner, filesystem cache, dynamic code loading or complete configuration dump. Internal narrow native-owner patches remain supported. A future **specific** external patch operation requires a real consumer and independent precondition/unowned-field tests.

`has_prototype` is unnecessary ceremony around native lookup. `get_extension_status` requires an authoritative cross-stage status mechanism that does not yet exist; do not invent a registry to justify that method. Bounded settings queries or small extension metadata may be added when an actual consumer needs them. Native technology declaration remains a supported integration route without MIR helper calls.

## Types and errors

Use Lua strings for stable IDs; booleans for actual flags; finite numbers with explicit native units; dense arrays where order/multiplicity matters; ordinary maps for named lookup. Do not convert all integer fields to a new ID/handle system. Avoid LuaObjects, callbacks, metatables and persistent-state references in public result records. At the public input boundary, reject cycles/executable values; limits should bound only the submitted record, not scan the world. Establish measured size/depth limits before API stabilization, without excluding historical valid data silently.

Runtime `ResearchStatus` exposes native semantics explicitly:

```text
name: string
force_index: integer
researched: boolean
level: integer                 # native current level, NOT universally completed count
enabled: boolean
saved_progress: number|null    # absent where unsupported; do not invent zero
max_level: number|"infinite"    # normalize only with a tested target adapter
```

Do not compute completed levels as `level - 1` for every finite or staged technology. Do not expose a derived total unless its family-specific semantics are defined. Missing/invalid force and missing technology are distinct results. Snapshot queries do not promise live subscription or ownership attribution from aggregate engine values.

Programming errors in explicit data calls fail with a stable prefix and contextual code, such as `MIR_API:invalid_definition`, `duplicate_identity`, `missing_target`, `unsupported_capability`, `unsupported_engine` or `ownership_conflict`. Optional integration absence is handled by the caller before mutation. Runtime queries return an unavailable/error result for expected missing state; they must not initialize storage, change research or throw merely because a requested optional technology is absent. Do not promise an `unsupported_api_version` error if the caller has not actually negotiated a version.

`API-03` — No claim that this API authenticates an extension's identity or sandboxes Lua. Mods sharing the data stage can bypass it. Runtime interface names may already have consumers: inspect existing registration before adding/replacing one. Never remove another interface to resolve a collision.

## Runtime registration

Register a small static function table at control parsing. No Generator import; no runtime `require` inside event or remote handlers. Query functions needing `game` are callable only in documented game-available contexts, not `on_load`. External mods own their event handlers and storage. MIR does not execute arbitrary foreign callbacks.

Factorio's remote transport copies arguments and does not preserve metatables; functions cannot be passed. That does not remove the need to return bounded, deliberate results or prove ownership in MIR's own data surface. [LuaRemote](https://lua-api.factorio.com/latest/classes/LuaRemote.html)

## SDK and conformance

`API-04` — The SDK contains examples, annotations and a small conformance entrypoint around actual MIR/native test commands, not another player implementation. Lua-first; add other-language tooling only for a named consumer. Never ship the SDK, schemas, test harness or evidence inside MIR's player ZIP.

Required cases: required dependency and optional absence; data versus final-fixes ordering; two extensions creating different names; duplicate same name; invalid field before writes; input/output mutation isolation; supported/unsupported capability; exact native effect; runtime query without mutation; save/reload and actual joining client; no private imports; old real consumer transition.

Optional `mod-data` metadata is a separate capability on engines that support it. Its absence must not prevent creating native research. No automatic interpretation of historical MEP fragments. [ModData](https://lua-api.factorio.com/latest/prototypes/ModData.html)

## Deterministic family API

`API-05` — `add_technologies` accepts a dense array of native technology tables, returns names in caller order, and checks the entire family before intentional publication. It permits local forward references through one name map. Duplicate IDs, references absent from both the family and current visible prototypes, local cycles or invalid consumed values reject the call before MIR writes. Single creation delegates to the same bounded path; an arbitrary global dependency plan is not created.

`add_technology` and `add_productivity` do not implicitly defer unresolved foreign references. A caller needing later upstream prototypes calls in its appropriate later round; a caller declaring a mutually related family uses the batch operation. This is why the batch is included now rather than adding a general pending-contribution registry.

`API-06` — Same complete ordered inputs give the same semantic result. Unordered capability maps do not convey priority. Return finite primitive/plain-table results; preserve documented native level semantics. `get_research` returns `nil, error_code` for an absent optional force/technology and performs no state initialization. Unknown methods still follow Factorio's native remote error behavior. Never remove or replace a foreign remote interface on collision.

A caller checks version and capability before performing its intended operation. Metadata is a capability report, not a support certificate. A single published API-major path may be implemented by multiple compatible MIR product releases. Do not create `api/mir5/`.
