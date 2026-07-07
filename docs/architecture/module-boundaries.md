---
title: "MIR 3.0.0 Repository Structure"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-08
supersedes: []
superseded_by: []
---
# MIR 3.0.0 Repository Structure

Updated: 2026-07-07

This note refines the `3.0.0` compatibility compiler plan into a concrete
repository structure. The organizing rule is:

```text
Factorio root files stay thin.
All meaningful shipped Lua lives under one MIR namespace.
Every module belongs to one compiler layer.
Only one layer mutates prototypes.
Compatibility overlays register policy, not behavior.
Development-only docs, scripts, fixtures, and tests stay outside the shipped zip.
Legacy paths become shims for backporting.
```

This is a target structure for the 3.0 refactor. It is not a requirement to move
every file before useful compiler work can continue.

## Factorio Shell

Factorio imposes the outer shell:

- the package has one `info.json`;
- root `settings*.lua` files define startup settings;
- root `data*.lua` files define prototypes;
- root `control.lua` is runtime scripting and should exist only when needed;
- `locale/` and `migrations/` are Factorio-recognized folders;
- the zip name follows `{mod-name}_{version}`;
- `info.json` has one `factorio_version`, so a single archive targets one
  Factorio major line.

That means MIR should not be structured like a normal application with dynamic
file I/O or arbitrary runtime loading. MIR is primarily a deterministic
data-stage compiler.

Before implementing this refactor, re-check these Factorio documentation
surfaces:

- `https://lua-api.factorio.com/latest/auxiliary/mod-structure.html`
- `https://lua-api.factorio.com/latest/auxiliary/data-lifecycle.html`
- `https://lua-api.factorio.com/latest/auxiliary/libraries.html`
- `https://lua-api.factorio.com/latest/auxiliary/changelog-format.html`
- `https://lua-api.factorio.com/latest/auxiliary/instrument.html`
- `https://wiki.factorio.com/Tutorial:Localisation`

Root files should stay thin:

```lua
require("prototypes.mir.stage.data_final_fixes").run()
```

Use that style for:

```text
settings.lua
settings-updates.lua
settings-final-fixes.lua
data.lua
data-updates.lua
data-final-fixes.lua
control.lua, only if runtime code is genuinely needed
```

`control.lua` is not part of the prototype compiler. It is Factorio's runtime
entrypoint for save/session behavior such as event handlers, commands, remote
interfaces, GUI, storage, and configuration-change handling. MIR should not add
or keep `control.lua` for normal generated technology emission. This branch
keeps it only because scripted technology candidates already have bounded
runtime handlers under `control/`.

Runtime control files must not inspect `data.raw`, call `data:extend`, or create
generated technology prototypes. Those responsibilities remain in the data
stage, primarily behind `data-final-fixes.lua`.

Current migration state: the Factorio root entrypoints route through
`prototypes/mir/stage/`. The runtime entrypoint
`prototypes/mir/stage/control.lua` owns only runtime registration and delegates
to the event handlers under `control/`. The old
`prototypes/mir/legacy/control.lua` path is a compatibility shim back to that
stage entrypoint. `prototypes/mir/stage/data_final_fixes.lua` owns the
transitional data-final-fixes call order and delegates old behavior through
`prototypes/mir/stage/data_final_fixes_steps.lua`. The old
`prototypes/mir/legacy/data_final_fixes.lua` path is now a compatibility shim
back to those stage steps. The generation modules still move behind `domain/`,
`capabilities/`, `planner/`, and `emit/` in later slices.

The first Factorio platform adapter is
`prototypes/mir/platform/factorio/data_raw.lua`. It wraps access to `data.raw`
and `data:extend` so emitters can depend on a narrow Factorio port instead of
calling global prototype mutation APIs directly.

The settings-stage active-mod adapter is
`prototypes/mir/platform/factorio/mods.lua`. Startup setting visibility may use
the active `mods` table because Factorio provides it during settings stage, but
it must not inspect `data.raw`: item, recipe, fluid, and technology prototypes
are not finalized until the later prototype stage.

The MIR settings namespace is `prototypes/mir/settings/`. It owns the startup
settings catalog, settings-stage visibility evaluation, and the adapter that
lets the legacy settings builder apply `hidden = true` without deleting setting
IDs or forcing values. Settings visibility uses `ui_visibility` metadata and
active mods only; final recipe, item, fluid, and technology facts remain
data-stage generation concerns.

The MIR planner namespace owns compiler planning checks as they are migrated out
of legacy generators. `prototypes/mir/planner/requirements.lua` evaluates
required mods, prototype families, technology gates, and legacy technology
requirement skip rules before the legacy recipe-productivity generator attempts
to build a stream. `prototypes/mir/planner/native_modifiers.lua` identifies
native technology modifiers and records overlap diagnostics through platform
prototype access before direct-effect streams are emitted.
`prototypes/mir/planner/science.lua` selects stream science ingredients and
normalizes lab-compatibility status while the rest of science integration moves
out of legacy utility modules. The focused utility split now routes stream
enablement, cost, growth, research-time, and max-level calculations through
`prototypes/mir/planner/costs.lua`; configured science-pack policy and
unlock-derived science selection through
`prototypes/mir/capabilities/science_integration/science_selector.lua`; and
stream prerequisite construction through
`prototypes/mir/planner/prerequisites.lua`. `prototypes/mir/policy/owner_policy.lua`
centralizes recipe-productivity owner filtering and the associated diagnostic
rows used by migrated stream planning. `prototypes/mir/policy/adoption_policy.lua`
wraps productivity-family adoption decisions while the underlying adoption
implementation is migrated out of the legacy compatibility path.
`prototypes/mir/planner/direct_effects.lua` prepares direct-effect streams by
asserting effect safety, dropping unavailable optional ammo categories, and
applying fallback effect icons before emission planning.
`prototypes/mir/capabilities/recipe_productivity/planner.lua` owns the current
recipe-productivity bucket matching facade and converts matched buckets into
recipe productivity effects after policy filters run.
`prototypes/mir/planner/stream_compiler.lua` owns the transitional generated
stream loop. The old `prototypes/tech-gen.lua` path is a compatibility shim
that immediately delegates to that MIR planner module.
`prototypes/mir/emit/legacy_stream_adapter.lua` adapts legacy stream records
into `StreamSpec` records and forwards them to `technology_builder`; the old
`prototypes/mir/legacy/stream_emitter.lua` path is now a compatibility shim.
`prototypes/mir/emit/base_extensions.lua` owns base technology continuation
prototype emission; the old `prototypes/base-tech-extensions.lua` root path is
now an execution shim for backport compatibility.
The old `prototypes/compat/` paths for profiles, owner detection, competing
productivity cleanup, competing base-extension cleanup, family adoption, and
compatibility planning are compatibility shims. The active implementations live
under `prototypes/mir/compatibility/`, `prototypes/mir/index/`, and
`prototypes/mir/policy/`.
The old `prototypes/lib/capabilities/` and `prototypes/lib/policy/capabilities.lua`
paths are also compatibility shims; the active capability contract, registry,
and policy live under `prototypes/mir/capabilities/` and
`prototypes/mir/policy/capabilities.lua`.

Compatibility policy uses `prototypes/mir/compatibility/`. Named compatibility
targets live under `prototypes/mir/compatibility/overlays/`; those overlays
register selectors, claims, deny rules, and policy overrides only. They must not
create technologies, call `data:extend`, or mutate `data.raw` directly.
Compatibility diagnostics may live under
`prototypes/mir/compatibility/diagnostics/` while legacy behavior is being
migrated, but they must read prototypes through platform adapters and emit rows
through `report/` helpers. The stage layer calls
`prototypes/mir/compatibility/diagnostics/registry.lua` rather than naming
individual exact-recipe diagnostic modules directly.
`prototypes/mir/report/diagnostics_sink.lua` owns the existing log/audit-row
diagnostic sink; the old `prototypes/diagnostics.lua` path is a compatibility
shim. During the transition it may call `prototypes/mir/emit/icon_builder.lua`
only to preserve existing icon-source hints in report rows; it must not mutate
prototypes.

## Three Workspaces

Use three clear workspaces:

```text
Factorio shell
  info.json
  changelog.txt
  thumbnail.png
  settings*.lua
  data*.lua
  control.lua if required
  locale/
  migrations/
  graphics/
  prototypes/

MIR compiler namespace
  prototypes/mir/stage/
  prototypes/mir/core/
  prototypes/mir/platform/
  prototypes/mir/domain/
  prototypes/mir/index/
  prototypes/mir/graph/
  prototypes/mir/classify/
  prototypes/mir/policy/
  prototypes/mir/settings/
  prototypes/mir/streams/
  prototypes/mir/capabilities/
  prototypes/mir/planner/
  prototypes/mir/emit/
  prototypes/mir/report/
  prototypes/mir/compatibility/
  prototypes/mir/legacy/

Development workspace
  docs/
  fixtures/
  scripts/
  tests/
  build/
  dist/
  todo.md
  CONTRIBUTING.md
```

Only the Factorio shell and shipped Lua/assets belong in the release archive.
Developer docs, fixtures, scripts, tests, build output, distribution output, and
task ledgers stay outside the mod zip.

## Target Module Tree

The long-term 3.0 layout should move toward:

```text
prototypes/
  mir/
    stage/
      settings.lua
      settings_updates.lua
      settings_final_fixes.lua
      data.lua
      data_updates.lua
      data_final_fixes.lua
      data_final_fixes_steps.lua
      control.lua

    core/
      schema.lua
      result.lua
      errors.lua
      ids.lua
      stable_sort.lua
      table.lua
      numbers.lua
      strings.lua
      deepcopy.lua
      log.lua

    platform/
      factorio/
        globals.lua
        mods.lua
        settings.lua
        data_raw.lua
        prototype_lookup.lua
        prototype_history.lua
        locale.lua
        dependency_order.lua
        feature_flags.lua

    settings/
      registry.lua
      visibility.lua
      builder.lua
      legacy_adapter.lua

    streams/
      registry.lua

    domain/
      facts/
        registry.lua
        recipe_fact.lua
        item_fact.lua
        fluid_fact.lua
        entity_fact.lua
        technology_fact.lua
        lab_fact.lua
        machine_fact.lua
        resource_fact.lua
        module_fact.lua
        owner_fact.lua
        rule_surface_fact.lua

      decisions/
        decision_record.lua
        decision_types.lua
        confidence.lua
        evidence.lua
        blocker.lua
        risk.lua

      streams/
        stream_spec.lua
        stream_manifest.lua
        stream_id.lua
        stream_target.lua

      claims/
        compatibility_claim.lua
        claim_level.lua

    index/
      registry_builder.lua
      recipes.lua
      items.lua
      fluids.lua
      entities.lua
      technologies.lua
      labs.lua
      machines.lua
      resources.lua
      modules.lua
      owners.lua
      rule_surfaces.lua

    graph/
      recipe_graph.lua
      technology_graph.lua
      science_graph.lua
      resource_chain_graph.lua
      ownership_graph.lua
      loop_risk.lua
      strongly_connected_components.lua

    classify/
      recipe_family.lua
      item_family.lua
      entity_family.lua
      machine_family.lua
      science_family.lua
      logistics_family.lua
      mining_family.lua
      ore_family.lua
      risk_flags.lua

    policy/
      defaults.lua
      capabilities.lua
      family_policy.lua
      science_policy.lua
      cap_policy.lua
      owner_policy.lua
      competing_productivity.lua
      competing_base_extensions.lua
      productivity_family_adoption.lua
      technology_cleanup.lua
      denylist.lua
      overrides.lua

    capabilities/
      registry.lua
      contract.lua

      recipe_productivity/
        capability.lua
        discover.lua
        classify.lua
        recipe_matching.lua
        propose.lua
        validate.lua
        emit.lua
        diagnose.lua

      native_modifiers/
        capability.lua
        owners.lua
        mining_yield.lua
        belt_stack.lua
        laboratory.lua
        robots.lua

      machine_manufacturing/
        capability.lua
        assemblers.lua
        furnaces.lua
        mining_drills.lua
        labs.lua

      logistics_manufacturing/
        capability.lua
        belts.lua
        undergrounds.lua
        splitters.lua
        loaders.lua

      ore_processing/
        capability.lua
        crushing.lua
        sorting.lua
        washing.lua
        smelting.lua
        casting.lua
        alloys.lua
        glass.lua

      science_integration/
        capability.lua
        science_packs.lua
        pack_detection.lua
        lab_matrix.lua
        prerequisite_planner.lua
        science_selector.lua

      rule_surfaces/
        capability.lua
        caps.lua
        modules.lua
        beacons.lua
        recyclers.lua
        surfaces.lua
        base_productivity.lua

    planner/
      compiler.lua
      candidate.lua
      classifier.lua
      costs.lua
      prerequisites.lua
      technology_requirements.lua
      scorer.lua
      proposal.lua
      validator.lua
      plan.lua
      diagnostics.lua

    emit/
      technology_builder.lua
      legacy_stream_adapter.lua
      base_extensions.lua
      effect_builder.lua
      prerequisite_builder.lua
      science_builder.lua
      locale_builder.lua
      icon_builder.lua
      manifest_writer.lua

    report/
      registry_summary.lua
      planner_report.lua
      decision_export.lua
      compatibility_diagnostics.lua
      diagnostics_sink.lua
      observation_export.lua
      claim_export.lua
      fixture_export.lua

    compatibility/
      registry.lua
      profiles.lua
      planner.lua
      overlay_loader.lua
      claim_registry.lua
      diagnostics/
        exact_recipe_policy.lua
        air_scrubbing.lua
        atan_ash.lua
      overlays/
        base.lua
        space_age.lua
        air_scrubbing.lua
        atan_ash.lua
        atan_nuclear_science.lua
        aai_industry.lua
        aai_loaders.lua
        bob_materials.lua
        krastorio2.lua
        krastorio2_spaced_out.lua
        angels.lua
        space_exploration.lua
        pyanodons.lua

    legacy/
      facts_registry.lua
      tech_gen.lua
      compat_profiles.lua
      report_rows.lua
```

The exact folder migration can be staged, but new 3.0 code should prefer this
shape.

## Layer Rules

| Layer | May read | May write | Must not do |
| --- | --- | --- | --- |
| `stage/` | Factorio globals, platform, planner | nothing directly | business logic |
| `platform/` | `data.raw`, `mods`, `settings` | `data:extend` only through emit path | classification or policy |
| `domain/` | plain Lua tables | plain Lua tables | Factorio globals |
| `index/` | platform facts | `FactRegistry` | policy decisions |
| `graph/` | `FactRegistry` | graph records | prototype mutation |
| `classify/` | facts and graphs | classifications | technology creation |
| `policy/` | settings, overlays, facts | policy decisions | prototype mutation |
| `settings/` | active-mod context and setting metadata | setting prototypes | `data.raw`, `forced_value` by default |
| `streams/` | explicit stream registry and compatibility profile overlays | stream config tables | prototype facts or prototype mutation |
| `capabilities/` | facts, classifications, policies | proposals | direct `data:extend` |
| `planner/` | analytical records | `DecisionRecord`, `StreamSpec` | direct prototype mutation |
| `emit/` | validated `StreamSpec` records | prototypes | classification |
| `report/` | records | report rows | prototype mutation |
| `compatibility/` | declarative selectors, policies, diagnostics | policy overlays and report rows | direct generation |
| `legacy/` | new modules | compatibility wrappers | new behavior |

Forbidden dependencies:

```text
domain/ must not require emit/
classify/ must not require platform/factorio/data_raw.lua
compatibility/overlays/ must not mutate data.raw
settings/ must not inspect data.raw or force hidden values by default
streams/ must stay declarative
report/ must not mutate data.raw
capabilities/ must not create technologies directly
legacy/ must not contain new business logic
```

## Ports And Adapters

The clean architecture is:

```text
Factorio adapter
  reads settings, mods, and data.raw
  writes prototypes only through emit/

MIR compiler core
  operates on facts, graphs, classifications, policies, decisions, and stream specs

Outputs
  technology prototypes
  reports
  fixture exports
  claim exports
  stream manifest
```

This gives MIR a real boundary between Factorio-specific access and pure
compiler logic.

## Capability Folder Pattern

Each capability should use the same internal pattern:

```text
capabilities/<capability_name>/
  capability.lua
  discover.lua
  classify.lua
  propose.lua
  validate.lua
  emit.lua
  diagnose.lua
```

`capability.lua` wires the pieces:

```lua
return {
  id = "loader_manufacturing",
  schema = 1,
  discover = require("prototypes.mir.capabilities.loader_manufacturing.discover"),
  classify = require("prototypes.mir.capabilities.loader_manufacturing.classify"),
  propose = require("prototypes.mir.capabilities.loader_manufacturing.propose"),
  validate = require("prototypes.mir.capabilities.loader_manufacturing.validate"),
  emit = require("prototypes.mir.capabilities.loader_manufacturing.emit"),
  diagnose = require("prototypes.mir.capabilities.loader_manufacturing.diagnose"),
}
```

The contract is:

```text
discover:
  FactRegistry -> Candidate[]

classify:
  Candidate -> ClassificationRecord

propose:
  ClassificationRecord + Policy -> Proposal

validate:
  Proposal + Registry + Graphs -> DecisionRecord

emit:
  Validated StreamSpec -> PrototypeMutation[]

diagnose:
  Rejected Proposal -> DecisionRecord
```

## Compatibility Overlay Format

Compatibility overlays should be declarative:

```lua
return {
  schema = 1,
  id = "aai_loaders",
  applies_when = {
    mods = { "aai-loaders" },
  },

  claims = {
    {
      level = "observed",
      capability = "loader_manufacturing",
      text = "MIR indexes AAI loader recipes and reports loader manufacturing productivity candidates.",
    },
  },

  capabilities = {
    loader_manufacturing = {
      mode = "propose",
      min_confidence = 0.92,
      selectors = {
        entity_types = { "loader", "loader-1x1" },
        require_item_place_result = true,
        require_recipe_result = true,
      },
      science = {
        mode = "derive_from_unlocks",
      },
      deny_risk_flags = {
        "hidden_internal",
        "recycling_loop",
        "recovery_loop",
      },
    },

    native_belt_stack = {
      mode = "observe",
      owner_policy = "prefer_existing",
    },
  },
}
```

Do not put these calls inside compatibility overlays:

```lua
data:extend(...)
add_productivity_technology(...)
```

The `mods` table selects policy. Prototype facts decide behavior.

## Legacy Shims

Backportability needs stable old paths during the 3.0 migration. Keep old paths
as wrappers while the compiler moves:

```lua
-- prototypes/lib/recipe-matching.lua
return require("prototypes.mir.capabilities.recipe_productivity.recipe_matching")
```

The shim may call new compiler modules, but new business logic belongs in the
3.0 namespace. The purpose is to reduce cherry-pick friction for `2.2.x`,
`2.5.x`, and target-line fixes while preserving clean architecture in `dev`.

## Naming Conventions

| Thing | Convention | Example |
| --- | --- | --- |
| Lua files | `lower_snake_case.lua` | `decision_record.lua` |
| Lua folders | `lower_snake_case/` | `science_integration/` |
| Lua modules | return one table | `local M = {}` |
| Prototype IDs | Factorio-style kebab | `mir-prod-air-scrubbing-clean-filter` |
| Locale keys | Factorio-style kebab | `mir-prod-clean-filter` |
| Docs | lowercase kebab | `decision-records.md` |
| Scripts | PowerShell verb-noun | `Invoke-MIRValidation.ps1` |
| Fixtures | lowercase kebab | `air-scrubbing/` |
| JSON artifacts | lowercase kebab | `decision-records.json` |

Avoid new files named only:

```text
utils.lua
helpers.lua
misc.lua
compat.lua
gen.lua
old.lua
new.lua
stuff.lua
```

Generic names are acceptable only in constrained folders such as `core/table.lua`
or `capabilities/registry.lua`.

## Dependency Strategy

For the Factorio `2.1` `3.x.x` line:

- keep `base >= 2.1.0` as the hard dependency;
- keep Space Age optional unless a release truly requires it;
- use hidden optional dependencies only for curated compatibility targets whose
  load order matters;
- avoid hundreds of optional dependencies;
- prefer diagnostics for unknown late-mutating mods;
- use incompatibilities only for known unsafe coexistence.

Curated hidden optionals may include major overhauls, known rule mutators,
native-owner mods, science/lab overhauls, loader ecosystems, and mining-drill
ecosystems. Add them because load order matters, not because MIR claims full
support.

## Data-Stage Reporting

Factorio mod Lua cannot use arbitrary filesystem output in normal mod code, so
MIR reports should remain split:

- in-game/data-stage report rows through logs, diagnostics, or generated
  prototype-visible surfaces where appropriate;
- development/audit exports through scripts that launch Factorio, parse logs,
  use fixtures, or use instrument-mode tooling.

Instrument mode is a development tool, not a shipped MIR package feature.

## Architecture Lints

Static validation should eventually fail when:

- `compatibility/overlays/` calls `data:extend`;
- `classify/` requires the Factorio `data_raw` adapter directly;
- `domain/` requires `emit/`;
- a capability emits without a `StreamSpec`;
- a generated stream lacks a manifest row;
- a public claim lacks a fixture;
- a policy auto-emits without `min_confidence`;
- a native modifier policy lacks `owner_policy`;
- root Factorio entrypoints contain business logic instead of stage wrappers.

The measurable transition debt report is:

```powershell
.\scripts\mir.ps1 legacy inventory --check
```

It writes `artifacts/legacy-inventory/shipped-mod-legacy.json`,
`artifacts/legacy-inventory/repo-legacy.json`, and
`artifacts/legacy-inventory/legacy-summary.md`. The report tracks old-path
module counts, shim-only status, old import counts, direct prototype access
matches, and generated stream manifest coverage. The checked form currently
requires zero active `prototypes/compat` modules, zero active `prototypes/lib`
modules, zero compat/lib/config/util/diagnostics imports, no more than the
current direct `data.raw` allowlist count outside the platform adapter, and
zero generated streams missing manifest rows.

## Implementation Sequence

1. Create the shell directories: `stage/`, `core/`, `platform/`, `domain/`, and
   `legacy/`.
2. Make root Factorio files call stage modules.
3. Move old code behind legacy shims without behavior changes.
4. Introduce or formalize schema records for `DecisionRecord`, `StreamSpec`,
   `FactRegistry`, `CompatibilityClaim`, and `StreamManifest`.
5. Move the current `2.2.0` planner into layers.
6. Add architecture lint gates.
7. Add report-only capabilities under the standard folder pattern.
8. Add one generated proof only if the compiler gates are stable; otherwise
   keep `3.0.0` as a pure architecture release and defer gameplay to `3.1`.

The design rule is:

```text
MIR 3.0 is not a refactor into more folders.
MIR 3.0 is a refactor into enforceable boundaries.
```
