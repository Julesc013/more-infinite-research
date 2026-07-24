---
title: "MIR 3.0.0 Repository Structure"
status: current
applies_to: "3.0.0+"
audience: maintainer
doc_type: explanation
owner: mir-maintainers
last_reviewed: 2026-07-24
supersedes: []
superseded_by: []
---
# MIR 3.0.0 Repository Structure

Updated: 2026-07-24

This note refines the `3.0.0` compatibility compiler plan into a concrete repository structure. The organizing rule is:

```text
Factorio root files stay thin.
All meaningful shipped Lua lives under one MIR namespace.
Every module belongs to one compiler layer.
Only one layer mutates prototypes.
Compatibility overlays register policy, not behavior.
Compatibility repairs are bounded schema or graph adapters, not broad behavior overlays. A graph repair must name the participating mods, prove the mutual prerequisite path from finalized prototypes, and remove only the single edge that closes the cycle.
Development-only docs, scripts, fixtures, and tests stay outside the shipped zip.
Old compatibility, library, legacy, and broad root-helper shim paths do not
ship on the main 3.x line.
```

This is the current structure target for the MIR 3 shipped mod. Backport branches may carry temporary compatibility surfaces only when branch policy requires them; those surfaces must not merge back into the main 3.x line.

## Factorio Shell

Factorio imposes the outer shell:

- the package has one `info.json`;
- root `settings*.lua` files define startup settings;
- root `data*.lua` files define prototypes;
- root `control.lua` is runtime scripting and should exist only when needed;
- `locale/` and `migrations/` are Factorio-recognized folders;
- the zip name follows `{mod-name}_{version}`;
- `info.json` has one `factorio_version`, so a single archive targets one Factorio major line.

That means MIR should not be structured like a normal application with dynamic file I/O or arbitrary runtime loading. MIR is primarily a deterministic data-stage compiler.

Before implementing this refactor, re-check these Factorio documentation surfaces:

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

`control.lua` is not part of the prototype compiler. It is Factorio's runtime entrypoint for save/session behavior such as event handlers, commands, remote interfaces, GUI, storage, and configuration-change handling. MIR should not add or keep `control.lua` for normal generated technology emission. This branch keeps it only because scripted technology candidates already have bounded runtime handlers under `prototypes/mir/runtime/`.

Runtime control files must not inspect `data.raw`, call `data:extend`, or create generated technology prototypes. Those responsibilities remain in the data stage, primarily behind `data-final-fixes.lua`.

Current state: the Factorio root entrypoints route through `prototypes/mir/stage/`. The runtime entrypoint `prototypes/mir/stage/control.lua` owns only runtime registration and delegates to event handlers under `prototypes/mir/runtime/`. `prototypes/mir/stage/data_final_fixes.lua` executes the deterministic command DAG and names no individual pass.

The first Factorio platform adapter is `prototypes/mir/platform/factorio/data_raw.lua`. It wraps access to `data.raw` and `data:extend` so emitters can depend on a narrow Factorio port instead of calling global prototype mutation APIs directly.

The settings-stage active-mod adapter is `prototypes/mir/platform/factorio/mods.lua`. Startup setting visibility may use the active `mods` table because Factorio provides it during settings stage, but it must not inspect `data.raw`: item, recipe, fluid, and technology prototypes are not finalized until the later prototype stage.

The MIR settings namespace is `prototypes/mir/settings/`. It owns the startup settings catalog, settings-stage prototype builder, settings-stage visibility evaluation, and the adapter that applies `hidden = true` without deleting setting IDs or forcing values. Settings visibility uses `ui_visibility` metadata and active mods only; final recipe, item, fluid, and technology facts remain data-stage generation concerns. `prototypes/mir/settings/resolver.lua` owns startup setting enablement checks for data-stage stream and base-extension planning. `prototypes/mir/settings/defaults.lua` owns shared stream and base-extension defaults. `prototypes/mir/settings/order.lua` owns global setting section ranges and generated-technology ordering helpers. `prototypes/mir/settings/pipeline_extent.lua` owns the pipeline extent setting catalog and parser. `prototypes/mir/pipeline/extent.lua` owns the optional pipeline extent prototype pass. `prototypes/mir/settings/prototype_limits.lua` owns the prototype-limit setting catalog and value parser. `prototypes/mir/pipeline/prototype_limits.lua` owns the optional data-final-fixes prototype mutation pass for selected recipe productivity and effect receiver limits. Recipe productivity caps apply only to non-parameter, non-recycling recipes. The same pass owns explicit generated recycler-return scaling because it is a global prototype-limit balance choice; it changes only eligible hidden generated recycler probabilities and never rewrites recycling-recipe productivity caps or visible processes such as scrap recycling. The optional inverse-return scope is inert at or below its threshold and uses the normal 25% generated return as the engine-unchanged baseline. Positive speed caps and negative speed floors remain independently selectable. `prototypes/mir/settings/effect_contracts.lua` consumes canonical typed per-level effect descriptors without inferring a primary effect from array position. Runtime setting lookup and scaling remain in `prototypes/mir/settings/effect_scaling.lua`, keeping catalog/profile loading acyclic.

`prototypes/mir/domain/streams/descriptor.lua` is the canonical normalization boundary for raw stream declarations. It attaches a schema, stable stream ID, stream kind, typed effect contract, and positive target-requirement record. Canonical anchors are selected semantically and are invariant under declaration order. `prototypes/mir/domain/streams/raw_catalog.lua` rejects duplicate IDs. Compatibility profiles may patch known raw declarations before normalization, but they may neither create an unknown stream nor inject a descriptor. `prototypes/mir/streams/registry.lua` keeps the canonical table private and returns deep copies through `snapshot()` and `get()`, so a consumer cannot mutate shared `require()` state.

`prototypes/mir/index/recipe_facts.lua` is the build-once normalized recipe authority. It scans final recipe prototypes once after target-local mutation passes, resolves target-aware effective recipe properties, preserves the full product shape, stores private copied facts, and builds output/category indexes. `prototypes/mir/index/recipe_risk_facts.lua` derives the one canonical RecipeRiskFact for every recipe, including hard and review flags, evidence confidence, shared input/output facts, and a risk fingerprint. Family rules, providers, packs, GenerationPlan rows, and diagnostics consume that same fingerprint; no consumer may recreate risk heuristics. Read-only consumers share the context-owned `view()`, `index_view()`, `for_each()`, cached `fingerprint()`, and `summary()` surfaces; complete deep-copied snapshots are reserved for callers that require ownership. `prototypes/mir/index/relationships.lua` owns separate immutable `input` and `output` indexes so post-emission assertions never reuse a pre-emission technology cache. Internal read-only consumers share `view(phase)`; `snapshot(phase)` is the defensive-copy boundary for exports and independently owned values. Recipe-productivity matching, science recipe-unlock facts, compatibility diagnostics, and the diagnostic registry query these authorities rather than rescanning `data.raw.recipe`. The shared owner lookup reuses the phase-scoped technology-effect view rather than deep-copying or scanning the complete relationship graph once per recipe.

`prototypes/mir/pipeline/compiler_context.lua` is the lifetime owner for mutable state and services derived from `data.raw`, startup settings, active mods, or the current compilation pass. CompilerContext schema 4 has no implicit activation in `new()` and exposes no public activation primitive; callers use packed, traceback-preserving `with_active(context, callback)` scopes at the Factorio adapter boundary, including nested A/B/A scopes and nil-bearing multiple returns. It owns recipe, recipe-risk, relationship, science-pack, graph-wide researchability, lab-input, compatibility-policy, family-resolution, ProviderMetrics, CompilerInput, TechnologyCatalog, qualifications, GenerationPlan, CompilationPlan, planned/final CompilerResult, TransformationPlan, MutationJournal, generated-technology, native-owner-adoption, graph-parity, coverage, telemetry, diagnostics, services, freeze state, and state epochs. Every compilation finalizes the exact schema-3 TechnologyCatalog; normal publication exposes only its compact bounded projection, while diagnostics or PREVIEW may expose the internal catalog. Services are registered per context and may be frozen before planning; science modules never configure process-global callbacks. State is set once unless the caller performs an explicit matching-epoch replacement, frozen state cannot be replaced, explicit diagnostic snapshots are observationally pure deep copies, and separate contexts cannot observe each other's derived state. Immutable generated provider, FamilyRule, promotion, and registered operator catalogs may remain module-scoped because they are source-owned policy inputs rather than run-derived compiler state.

`prototypes/mir/report/public_compiler_artifacts.lua` owns compact schema-1 projections for normal-load GenerationPlan, coverage, and CompilerEvidence publication. Full stream specifications, `TechnologyDesign` objects, recipe rows, sanitation ledgers, exact provider resolution, and graph-parity evidence remain internal compiler state and are emitted through separately named `*-internal` prototypes only when generation diagnostics or automatic compiler preview/report mode requests them. Downstream validators consume those immutable projections; they do not keep a compiler context active after the scoped MIR run.

`prototypes/mir/planner/generation_plan.lua` is the side-effect-free boundary between stream proposal planning and emission. The compiler validates duplicate stream, manifest, technology, adoption, and semantic effect identities across the whole set before application. Evidence-bearing gates have explicit `not-applicable`, `pending`, `passed`, `failed`, and `superseded` states. `prototypes/mir/planner/compilation_plan.lua` is the compatibility finalizer over immutable `CompilerInput`: it normalizes base continuations, applies sanitation and graph policy through planner-safe integrity services, and finalizes the schema-3 `TechnologyCatalog` without importing an emitter. `prototypes/mir/planner/compiler.lua` is the pure `compile(snapshot, policy)` boundary and the sole producer of executable `TransformationOperation` rows. `prototypes/mir/pipeline/compiler_orchestrator.lua` owns capture, sequencing, context state, apply, output assertion, and exact artifact publication.

`prototypes/mir/pipeline/commands.lua` is the explicit execution boundary for data-final-fixes passes. Every pass has a stable command ID, kind, phase, dependency list, owned implementation, and positive target feature requirements. The registry validates dependencies, rejects cycles, exposes a deterministic topological order, and runs the entire graph. The graph governs compilation, stream and base-extension apply, diagnostics, output validation, safety assertions, and diagnostic flushing. Stage wrappers preserve Factorio lifecycle order but do not name or invoke mutators directly. Emission commands are the only commands allowed to create generated technology prototypes; mutation commands may update existing prototypes only through their declared implementation. The exact-version compatibility repair remains separately bounded and audited.

Effect contracts separate semantic identity from canonical, selected, and emitted numeric values. `prototypes/mir/domain/effects/metadata.lua` is the single authority for identity fields and native-versus-percentage numeric metadata; descriptor normalization and settings contracts consume it instead of carrying parallel tables. Owner discovery may use semantic identity, while external adoption and replacement policy decide independently whether numeric equivalence is required. Competing technology removal is committed through `prototypes/mir/emit/technology_replacement.lua` only after registered emitted coverage exists and the rewritten prerequisite graph is acyclic.

The MIR planner namespace owns compiler planning checks as they are migrated out of legacy generators. `prototypes/mir/planner/requirements.lua` evaluates required mods, prototype families, technology gates, and legacy technology requirement skip rules before the recipe-productivity planner builds a stream. `prototypes/mir/planner/native_modifiers.lua` identifies native technology modifiers and records overlap diagnostics through platform prototype access before direct-effect streams are emitted. `prototypes/mir/planner/science.lua` selects stream science ingredients and normalizes lab-compatibility status. Science integration is decomposed into `pack_registry.lua`, `lab_compatibility.lua`, `recipe_unlock_facts.lua`, `technology_researchability.lua`, `pack_production_reachability.lua`, and `science_selection_policy.lua`; `science_packs.lua` is only the stable facade and dependency-wiring boundary. The focused utility split routes stream enablement, cost, growth, research-time, and max-level calculations through `prototypes/mir/planner/costs.lua`; configured science-pack policy and unlock-derived science selection through `prototypes/mir/capabilities/science_integration/science_selector.lua`; and stream prerequisite construction through `prototypes/mir/planner/prerequisites.lua`. `prototypes/mir/policy/owner_policy.lua` centralizes recipe-productivity owner filtering and the associated diagnostic rows used by stream planning. `prototypes/mir/policy/adoption_policy.lua` wraps productivity-family adoption decisions. `prototypes/mir/planner/direct_effects.lua` prepares direct-effect streams by asserting effect safety, dropping unavailable optional ammo categories, and applying fallback effect icons before emission planning. `prototypes/mir/capabilities/recipe_productivity/planner.lua` owns the recipe-productivity bucket matching facade and converts matched buckets into recipe productivity effects after policy filters run. `recipe_productivity/recipe_matching.lua` may discover module recipe outputs from final `ModulePrototype.tier` facts. Stream data selects tier ranges; it does not hard-code third-party module mod IDs. `prototypes/mir/index/recipe_unlocks.lua` builds the immutable recipe-to-unlock technology fact index. Science selection, prerequisite planning, and explicit technology requirements apply shared iterative researchability policy to those facts instead of rescanning technology prototypes independently. `prototypes/mir/planner/stream_compiler.lua` owns the generated stream decision loop and finalized GenerationPlan artifact only; it does not import prototype mutation transactions. `prototypes/mir/emit/stream_executor.lua` owns application of accepted stream and adoption operations. `prototypes/mir/emit/technology_design_adapter.lua` is the common create/continuation prototype emitter; both the stream adapter and base-continuation path consume it. `prototypes/mir/emit/base_extension_builder.lua` constructs the initial allowlisted continuation alternative without copying arbitrary third-party prototype state. `prototypes/mir/planner/technology_graph.lua` validates the combined existing-plus-planned graph with iterative strongly connected components before emission. The 3.x shipped layout has no `prototypes/compat/`, `prototypes/lib/`, or `prototypes/mir/legacy/` implementation roots. Active compatibility, indexing, policy, capability, and report code lives under focused `prototypes/mir/` namespaces.

Compatibility policy uses `prototypes/mir/compatibility/`. `policy_authority.lua` is the sole planning facade that composes overlays, active CompatibilityPacks, support claims, source authorities, and their context-local fingerprint. Named compatibility targets live under `prototypes/mir/compatibility/overlays/`; those overlays register selectors, claims, deny rules, and policy overrides only. They must not create technologies, call `data:extend`, or mutate `data.raw` directly. Compatibility diagnostics may live under `prototypes/mir/compatibility/diagnostics/`, but they must read prototypes through platform adapters and emit rows through `report/` helpers. The stage layer calls `prototypes/mir/compatibility/diagnostics/registry.lua` rather than naming individual exact-recipe diagnostic modules directly. Exact upstream loader-schema repairs may live under `prototypes/mir/compatibility/repairs/` when they are version-gated, recipe-ID-gated, and limited to schema normalization required for Factorio to construct prototypes. These repairs may mutate existing third-party prototype fields through the platform adapter, but they must not generate technologies, change ingredients, change results, change unlocks, or alter balance. `prototypes/mir/report/diagnostics_sink.lua` owns the log/audit-row diagnostic sink and counts bounded telemetry rows. It may call `prototypes/mir/emit/icon_builder.lua` only to preserve existing icon-source hints in report rows; it must not mutate prototypes. Policy modules for competing productivity, competing base extensions, productivity-family adoption, max levels, and weapon-speed overlap return deterministic plans only. `prototypes/mir/pipeline/mutations/` owns post-plan technology replacement and field assignment, while `prototypes/mir/emit/transactions/productivity_family_adoption.lua` owns planned owner-effect insertion and adoption evidence. That transaction may mutate only after it validates the schema-2 patch-existing TechnologyDesign projection, target, operation, immutable input fingerprint, and expected output fingerprint. `prototypes/mir/integrity/effect_contracts.lua` is the shared identity and target-reference authority for known effect types. Generation planning, relationship indexes, sanitation, duplicate ownership, and output assertions consume that authority instead of defining effect identities independently. `prototypes/mir/emit/effect_safety.lua` uses those contracts to sanitize impossible known targets in generated and external technology effects, retains unknown effect types rather than guessing, and asserts registered generated technology postconditions.

The technology graph semantics no longer belong separately to planner and emitter code. `prototypes/mir/graph/` is the shared non-mutating kernel for canonical snapshots, iterative strongly connected components, condensation, reachability, researchability, the graph-wide researchability index, qualification, diff, and proof evidence. `planner/technology_graph.lua` and `emit/technology_graph_safety.lua` are adapters: virtual and realized graphs bind exact graph, component-assignment, condensation, and proof fingerprints before parity is accepted.

Presentation construction lives in `prototypes/mir/presentation/icon_builder.lua`; `emit/icon_builder.lua` is a compatibility facade. Pure blocked-effect policy lives in `domain/technology/effect_safety_policy.lua`, while the emit facade owns mutation. `.mir/module-dependencies.json` and `scripts/Test-MIRModuleDependencies.ps1` enforce forbidden planner-to-emitter imports, overlay mutation boundaries, command authority, and an exact bounded baseline for the few remaining legacy cycles.

### Technology Catalog Construction Ownership

`prototypes/mir/planner/stream_compiler.lua` produces source rows and the finalized GenerationPlan only. It must not construct a transient TechnologyCatalog. `prototypes/mir/planner/compilation_plan.lua` is the sole TechnologyCatalog construction and finalization owner after the complete operation set is known, and its final catalog receives the full schema validation before publication.

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

Only the Factorio shell and shipped Lua/assets belong in the release archive. Developer docs, fixtures, scripts, tests, build output, distribution output, and task ledgers stay outside the mod zip.

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
      stage_adapter.lua

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
      max_level.lua
      weapon_speed.lua
      owner_policy.lua
      competing_productivity.lua
      competing_base_extensions.lua
      productivity_family_adoption.lua
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
      technology_replacement.lua
      technology_builder.lua
      stream_spec_adapter.lua
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
      repairs/
        factorio_2_1_recipe_schema.lua
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

```

The exact folder migration can be staged, but new 3.0 code should prefer this shape.

## Layer Rules

| Layer | May read | May write | Must not do |
| --- | --- | --- | --- |
| `stage/` | Factorio globals, platform, planner | nothing directly | business logic |
| `platform/` | `data.raw`, `mods`, `settings` | `data:extend` only through emit path | classification or policy |
| `domain/` | plain Lua tables | plain Lua tables | Factorio globals |
| `index/` | platform facts | `FactRegistry` | policy decisions |
| `families/` | RecipeFactV2 and relationship indexes | data-only family decisions and attach proposals | prototype reads or mutation |
| `graph/` | `FactRegistry` | graph records | prototype mutation |
| `classify/` | facts and graphs | classifications | technology creation |
| `policy/` | settings, overlays, facts | policy decisions | prototype mutation |
| `settings/` | active-mod context and setting metadata | setting prototypes | `data.raw`, `forced_value` by default |
| `streams/` | explicit stream registry and compatibility profile overlays | stream config tables | prototype facts or prototype mutation |
| `capabilities/` | facts, classifications, policies | proposals | direct `data:extend` |
| `planner/` | analytical records | `DecisionRecord`, `StreamSpec` | direct prototype mutation |
| `emit/` | validated `StreamSpec` records | prototypes | classification |
| `report/` | records | report rows | prototype mutation |
| `compatibility/` | declarative selectors, policies, diagnostics, exact-version loader-schema repair specs | policy overlays, report rows, and bounded schema normalization | direct generation or balance changes |

Forbidden dependencies:

```text
domain/ must not require emit/
classify/ must not require platform/factorio/data_raw.lua
compatibility/overlays/ must not mutate data.raw
compatibility/repairs/ must not generate technologies or change gameplay semantics
settings/ must not inspect data.raw or force hidden values by default
streams/ must stay declarative
families/ must consume copied facts and must not read data.raw
report/ must not mutate data.raw
capabilities/ must not create technologies directly
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

This gives MIR a real boundary between Factorio-specific access and pure compiler logic.

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

The capability registry enforces this as an explicit state machine. Loader manufacturing, mining-drill manufacturing, and native-modifier ownership pass distinct discovered, classified, proposed, validated, materialized, and result states. Materialization records a decision or existing stable-stream ownership; it does not emit prototypes. The loader and drill paths consume structural item/place-result/entity/recipe evidence and existing owner facts; named mods only supply fixtures. Science and lab acceptance remain hard gates in the shared science fact modules rather than mod-name branches.

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

## No Shims

MIR 3 dev must not keep old implementation paths as active shims. Backports may carry temporary compatibility surfaces on their own branch, but the main 3.x line keeps the shipped implementation under `prototypes/mir/` plus the required Factorio root entrypoints and stream data tables. The legacy inventory gate fails if deleted shim directories or broad root helper files return.

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

Generic names are acceptable only in constrained folders such as `core/table.lua` or `capabilities/registry.lua`.

## Dependency Strategy

For the Factorio `2.1` `3.x.x` line:

- keep `base >= 2.1.0` as the hard dependency;
- keep Space Age optional unless a release truly requires it;
- use hidden optional dependencies only for curated compatibility targets whose load order matters;
- avoid hundreds of optional dependencies;
- prefer diagnostics for unknown late-mutating mods;
- use incompatibilities only for known unsafe coexistence.

Curated hidden optionals may include major overhauls, known rule mutators, native-owner mods, science/lab overhauls, loader ecosystems, and mining-drill ecosystems. Add them because load order matters, not because MIR claims full support.

## Data-Stage Reporting

Factorio mod Lua cannot use arbitrary filesystem output in normal mod code, so MIR reports should remain split:

- in-game/data-stage report rows through logs, diagnostics, or generated prototype-visible surfaces where appropriate;
- development/audit exports through scripts that launch Factorio, parse logs, use fixtures, or use instrument-mode tooling.

Instrument mode is a development tool, not a shipped MIR package feature.

## Validation Tooling Boundary

`scripts/Invoke-MIRValidation.ps1` remains the stable validation facade. Reusable concerns live under `scripts/validation/`: package identity, target metadata, scenario grouping, structured evidence aggregation, and Factorio process/copied-mod handling. Extracted modules receive paths explicitly and must retain the facade's existing parameters, scenario names, group assignments, and schema-2 result contract.

The process module owns hidden process launch, timeout termination, safe copied-mod replacement, and release-shaped source copying. The settings-override module owns deterministic edits to the copied mod's declarative test override table. The scenario registry imports one target profile from the expected-scenario manifest, rejects duplicate or undeclared names, and resolves every gate, runtime, configuration-change, and package invocation through a target-bound declaration record. Scenario orchestration may call these modules but must not reimplement their operations inline.

Running evidence is an expiring coordination marker with an explicit `process` or `ci-job` lease scope. Same-host process leases bind both PID and process start time so PID reuse cannot revive a stale owner. Same-job CI leases bind run ID, attempt, job, and host identity; a marker from another trusted CI job is adopted only while its trust-class-matched lease remains unexpired, without attempting to inspect a remote PID. Invalid, expired, or untrusted markers are removed and scheduled again. A matching live worker is adopted instead of cancelled or duplicated; running evidence is not a substitute for an immutable passing capsule.

## Museum Build Compiler Boundary

Factorio 0.12 through 0.6 use a development-time compiler under `scripts/Museum/`. `.mir/canonical-lower-features.json` owns the target-neutral feature, effect, cost, prerequisite, ownership, locale, balance, and test contracts; `.mir/museum-targets.json` owns only portable target facts, immutable binary/base-data fingerprints, installation IDs, relative installation paths, and named feature projections. It must not contain a workstation path. The compiler resolves every emitted family from canonical feature IDs and fails on unknown IDs or projection drift. It executes in the maintainer's current PowerShell environment; it does not ship in, or execute inside, an old Factorio runtime. It emits only finite numbered technology prototypes, target-era `info.json` with an explicit target-matching `factorio_version`, a loaded `config.lua`, English CFG locale rows, stable stream-manifest rows, and balance evidence.

Museum compatibility data is declarative and cannot mutate prototypes. The PowerShell emitter is the only museum component allowed to create target technology source. Each target branch materializes its own output directly from the canonical feature model, its target projection, and matching base files; no lower target branch supplies source to another target. Release archives contain only `info.json`, `config.lua`, `data.lua`, and `locale/en/more-infinite-research.cfg` beneath the versioned mod directory.

`static.museum` validates catalog schema, canonical projections, effect and balance contracts, generated IDs/prerequisites, all synthetic negative cases, and deterministic renderer output against the repository-owned synthetic installation; it never resolves a historical Factorio install. `runtime.museum-exact` is a separate self-hosted archival profile. It resolves each `installation_id` through `-InstallationRoot`, `MIR_MUSEUM_ROOT`, or an ignored/protected registry selected by `-RegistryPath` or `MIR_MUSEUM_INSTALLATION_REGISTRY`, then verifies the exact executable and complete base-data tree before checking evidence files and icons or launching Factorio.

The museum runtime harness uses the target's isolated write-data directory and actual legacy CLI surface. The campaign first proves one generated technology from a directory package. Factorio 0.12 then proves the exact deterministic ZIP by fresh create and bounded server reload. Factorio 0.11 and 0.10 prove two bounded GUI startup loads from the exact ZIP through target logs. Factorio 0.9 proves two cache-regenerating startup loads from the exact ZIP. Factorio 0.8 through 0.6 do not discover ZIP mods, so the harness copies and extracts the exact deterministic ZIP before two cache-regenerating startup loads. Pre-0.11 installer config-path changes are transactional and must be restored byte-for-byte. A patch or installation fingerprint mismatch remains an input failure and cannot be waived by static evidence from a nearby binary.

## Compiler boundary

MIR separates pure planning from lifecycle orchestration. `pipeline/compiler_orchestrator.lua` owns capture, compile, apply, output assertion, and artifact publication. `planner/compilation_plan.lua` normalizes legacy proposals, sanitation, and graph proof without importing `emit/`; `planner/compiler.lua` accepts only immutable `CompilationSnapshot` and `PolicySnapshot` records and returns the executable `TransformationPlan`. Planner-safe technology-effect checks live under `integrity/`.

The context-owned schema-3 `TechnologyCatalog` is finalized once, after sanitation and graph proof, and published exactly. It preserves rejected designs, contains total authoritative hard-gate vectors, and binds exact GenerationPlan and CompilationPlan fingerprints. `ProviderMetrics` binds every provider result to its exact environment and semantic partition. Missing measurements stay incomplete; ambiguity stays review-required.

`prototypes/mir/core/trusted_record.lua` owns the validation-once boundary for immutable compiler records. Each record module owns a private weak-key authority: `verify_untrusted(record)` performs complete schema, cross-field, and fingerprint verification before registration, while `assert_trusted(record)` checks private membership and stable scalar identity without canonicalizing the complete record. Constructors register only records whose values they own. Defensive copies, decoded artifacts, captured snapshots, and other externally owned values lose trust and must re-enter through deep verification. A copied public field cannot forge authority. Complete catalog snapshots and final postcondition validation remain explicit defensive boundaries; normal planning shares trusted designs, gates, qualifications, operations, and plans by reference.

Compiler telemetry records fingerprint calls, canonicalized bytes, large serializations, trusted assertions, untrusted deep verifications, full-record copies, and explicit catalog snapshots. The Base integrity fixture binds ceilings with headroom and requires zero trusted-assertion canonicalizations, rejected assertions, catalog snapshots, and full-record copies in normal mode. These deterministic counters supplement, but do not replace, the paired wall-clock performance gate.

## Compiler boundary closure

`prototypes/mir/planner/compiler.lua` is the pure compiler entry point. Its complete arguments are normalized `CompilationSnapshot` schema 2 and `PolicySnapshot` schema 1. It may require only deterministic core/domain/planner contracts; direct or transitive reads of `data.raw`, settings, loaded mods, logging, clocks, telemetry, or `CompilerContext` are forbidden. `pipeline/compilation_snapshot_adapter.lua` and `pipeline/policy_snapshot_adapter.lua` compose the outer Factorio and governance adapters. Snapshot capture may consume canonical index, graph, platform, and capability fact registries; those dependencies end at the adapter and do not enter the pure compiler.

`CompilerContext` schema 4 has scoped activation. `new()` never changes active state. `with_active()` restores the outer context on normal return and error. Effective settings import state and competing-technology preparation belong to context state, and architecture validation rejects their former mutable module globals.

`.mir/technology-hard-gates.json` and `.mir/technology-effect-targets.json` are generated authorities. Every hard-gate vector is exact and total. A not-applicable result binds an evaluator, predicate, input fingerprint, false result, and evidence. Missing gates, unknown gates, remote target inspection, or an unevidenced N/A are errors.

Base continuations are planned in `planner/base_continuations.lua`, executed in `emit/base_continuation_executor.lua`, and recorded as accepted or rejected catalog candidates. Streams, continuations, and native-owner patches produce common `TransformationOperation` envelopes. `emit/technology_operation_executor.lua` owns all technology create/patch mutation and can write exact before/after evidence to `MutationJournal`.

Provider identities are provenance, not a tie-breaker. `ProviderClaim` fingerprints the subject, semantic partition, stream, effect, policy, evidence, and risk. Identical claims collapse with every provider identity and evidence row preserved; any same-stream semantic disagreement is review-required.

All cross-layer imports are declared in `.mir/module-dependencies.json`. The matrix is exhaustive: every allowed edge must occur, every observed edge must be allowed, and exceptions are forbidden.

## Architecture Lints

Static validation should eventually fail when:

- top-level MIR Lua imports form a dependency cycle;
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

It writes `artifacts/legacy-inventory/shipped-mod-legacy.json`, `artifacts/legacy-inventory/repo-legacy.json`, and `artifacts/legacy-inventory/legacy-summary.md`. The report tracks old-path module counts, deleted shim-directory presence, old root helper presence, old import counts, direct prototype access matches, and generated stream manifest coverage. The checked form requires zero old shim directories, zero old root helper files, zero runtime Lua files under `control/`, zero MIR-legacy/compat/lib/config/util/diagnostics imports, zero direct `data.raw` matches outside the platform adapter, and zero generated streams missing manifest rows.

## Implementation Sequence

1. Create the shell directories: `stage/`, `core/`, `platform/`, and `domain/`.
2. Make root Factorio files call stage modules.
3. Move old code into MIR-owned namespaces without behavior changes.
4. Introduce or formalize schema records for `DecisionRecord`, `StreamSpec`, `FactRegistry`, `CompatibilityClaim`, and `StreamManifest`.
5. Move the current `2.2.0` planner into layers.
6. Add architecture lint gates.
7. Add report-only capabilities under the standard folder pattern.
8. Add one generated proof only if the compiler gates are stable; otherwise keep `3.0.0` as a pure architecture release and defer gameplay to `3.1`.

The design rule is:

```text
MIR 3.0 is not a refactor into more folders.
MIR 3.0 is a refactor into enforceable boundaries.
```
