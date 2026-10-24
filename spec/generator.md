---
title: "MIR Generator"
status: proposed
applies_to: "MIR replacement development"
audience: developer
doc_type: specification
owner: mir-maintainers
last_reviewed: 2026-10-22
supersedes: []
superseded_by: []
source_of_truth_for:
  - mir-replacement-generator-specification
---

# MIR Generator

## Contract

`GEN-01` — The Generator constructs selected native research. It does not discover research subjects, infer factory routes, solve global progression, choose between unrelated owners, host third-party callbacks, or produce proof artifacts.

It executes during the Factorio **prototype/data stage**, not only offline. A complete arbitrary mod configuration is not known when MIR is packaged. Build-time tooling may extract/verify definitions and prepare fixed target files, but players never need to run a precompiler. Runtime, migrations and Library do not load the Generator.

## Input and flow

```text
small activation checks
  → relevant settings resolved once
  → explicit compatibility variant/binding
  → authored native definition and effect targets
  → check required fields/references and named owner assumptions
  → build owned native output
  → publish once through data:extend or a narrow explicit patch
```

An internal family module can directly construct native tables. Shared helpers are optional conveniences, not compulsory layers. No runtime parsing of a JSON catalogue, general normalization envelope, dependency plan or binary artifact.

Inputs are ordinary selected Lua definitions, effective startup values, exact `data.raw` references, relevant `mods` entries and the selected target capability table. They do not include a save or runtime force state.

## Functions and representations

The first implementation may combine functions. The following describes boundaries rather than requiring four wrappers:

| Function | Responsibility |
|---|---|
| `eligible(definition, environment)` | Check only authored applicability; return a named outcome, not a universal boolean that hides conflicts. Usually owned by the family/compatibility module. |
| `build(prototype, resolved_values)` | Return one owned native prototype, without changing inputs or `data.raw`. No unneeded intermediate record. |
| `emit(prototype)` | Check duplicate identity and publish the already checked table. Do not return private state. |
| `generate(definitions, settings)` | Optional simple ordered loop. It is not a scheduler or registration registry. |

Prefer native field names: `name`, `effects`, `prerequisites`, `unit.count`/`unit.count_formula`, `unit.ingredients`, `unit.time`, `max_level`, `icons`, `localised_name`. Avoid a second public model using `science`, `time`, `base_cost`, `growth` as replacements for every native field. Internal convenience parameters may format a known existing cost model; they are not a formula language.

`GEN-02` — Typed references retain item/fluid/ammo/recipe distinctions. Science is not universally limited to `data.raw.tool`: each target's documented research ingredient rules apply. A valid formula, effect and asset reference must be accepted by the pinned native engine; host table tests cannot replace that validation.

## Calculations

Resolve the inherited setting/default/profile precedence, select the correct finite stage and continuation, construct the intended per-level effect value, and preserve the exact cost/formula/time semantics. Preserve native-owner defaults where the historical setting means inherit.

For a family whose **actual** approved model is `B * G^(L-L0) + D*(L-L0)`, format that native formula once. This is an example, not a new universal formula or authority to change historical tuning. Other numeric/formula models retain their own rules. Do not enumerate future infinite levels. Native `L` refers to the actual technology level, including its starting suffix; test boundary levels and finite completion.

Reject NaN, infinity, invalid ranges and unsupported shapes in consumed values. Preserve the numeric precision/rounding supported by the target and existing contract. A configured cap below earned research is a runtime/migration issue, not justification to truncate stored progress during construction.

## Data ownership and writes

`GEN-03` — The illustrative assignment `effects = definition.effects` is not sufficient isolation when either side can be mutated later. Build fresh effect/prerequisite/science arrays or transfer exclusive ownership explicitly. A shared reusable template must remain unaffected by output mutation and vice versa.

Owned internal input need not be hashed or copied repeatedly. At the external API boundary, make one bounded plain-data copy or construct owned fields once; reject cycles, metatables and executable values. Do not build a separate validated descriptor plus a second full output copy if one owned native result suffices.

For a finite family, precheck its names and required fields before making its first write. For a patch, inspect only relevant expected fields, preserve all unrelated fields, compute new values locally, then assign the declared fields. No speculative mutation followed by a generic rollback engine.

`GEN-04` — MIR-controlled preflight rejection makes no writes. This is not a promise of an engine-level transaction across arbitrary `data:extend` failures. If native validation fails, loading fails; do not catch and resume a partially modified shared state.

## Order and identity

Use an authored sequence where relative order matters. Do not depend on arbitrary input order for owner priority. Avoid sorting an already ordered catalogue on every launch. Necessary canonical presentation order for a bounded collector is measured separately; a local sort is not prohibited merely because a slogan said every operation must be linear.

Native initial IDs, finite stages, infinite continuations and hidden migration carriers remain their historical identities. Product version is metadata, not a prefix added to every prototype.

`GEN-05` — Each definition is emitted once per declared invocation. A repeated API creation of the same ID is a duplicate error, not silent success. Native-owner retention/extension is an explicit compatibility decision, not an implicit fallback when a name exists.

## Required tests

Build purity and alias isolation; exact expected prototypes under defaults and changed settings; malformed input before writes; numeric/formula alternatives; typed missing targets; duplicate IDs; finite tail/infinite continuation; disabled new feature versus historical identity; target-native acceptance and physical researched effects. Instrument only diagnostic builds to count touched references and allocations; normal player builds do not create per-field logs or hashes.

[TechnologyPrototype](https://lua-api.factorio.com/latest/prototypes/TechnologyPrototype.html) and [TechnologyUnit](https://lua-api.factorio.com/latest/types/TechnologyUnit.html) define the native representation. Verify exact target behavior before graduation.

## Family preflight and publication boundary

`GEN-06` — A submitted finite family is one local preflight unit. Build a local name map once and validate references against both that map and current relevant native prototypes. Forward references within the family are permitted; a valid prerequisite need not already be installed. Check duplicate IDs, self references and local family cycles in O(V_family + E_family); this is not a whole-game researchability solver. All MIR-controlled checks complete before the first intended write. Final engine validation and later foreign mutations remain outside a rollback guarantee.

Two output classes remain distinct: new MIR-owned prototypes go through creation; changes to an established native owner use a separately authored narrow patch with checked preconditions and preservation of unowned fields. Do not disguise patching as duplicate-tolerant creation.

`GEN-07` — Construction is a deterministic function of explicit resolved values. `build` does not read the current save, wall clock, global RNG or unrelated world state. It constructs detached nested output or receives explicitly exclusive internal ownership. The public API never offers a bypass named "trusted" to skip checks. See [determinism](determinism.md).

A disabled setting is resolved against the family's continuity policy **before** omission. The data stage cannot inspect whether this particular save researched an identity. Released identities have an authored availability/preservation policy for the supported configuration, not a conditional "keep it only if researched" query at data time.
