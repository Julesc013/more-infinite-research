# M.I.R. Roadmap

Updated: 2026-07-01

This is the current release roadmap for More Infinite Research after the v2.0.0 Factorio 2.1 compatibility release.

Use this document for release intent and scope. Use `docs/todo.md` for the executable checklist. Use `docs/post-2.0-feature-plan.md` for the long-form feedback archive and API notes behind these decisions.

## Current Baseline

The current development baseline is mod version `2.0.5` on the Factorio `2.1` line.

Already implemented in the v2.0.5 development slice:

- A narrow `control.lua` runtime surface for bounded scripted technologies.
- `control/scripted-techs.lua` for init, configuration change, research finish, research reversal, technology-effects reset, and agricultural tower planting handlers.
- Scripted spoilage preservation research using a visible `nothing` effect and the global spoil time modifier.
- Scripted agricultural growth speed research using agricultural tower planting events and plant `tick_grown`.
- Electric shooting speed coverage for both `tesla` and `electric` ammo categories, so Tesla guns, Tesla turrets, and discharge-defense-style equipment are all covered where the categories exist.
- Recipe-productivity duplicate prevention for recipes already owned by another infinite recipe-productivity technology.
- Space Age vanilla productivity technologies remain authoritative for processing units, low density structures, plastic, and rocket fuel instead of receiving parallel MIR technologies.
- Package and validation script coverage for `control.lua`, the control module tree, Tesla speed assertions, and vanilla Space Age productivity skip assertions.
- A v2.0.5 development package at `dist/more-infinite-research_2.0.5.zip`.

The remaining v2.0.5 work is validation, hardening, and a few small decisions. It should not expand into a full logistics, quality, refrigeration, or agriculture content release.

## Product Boundary

More Infinite Research belongs in one of these lanes:

| Lane | Belongs in MIR? | Examples |
| --- | ---: | --- |
| Native technology modifiers | Yes | cargo bay unloading distance, worker robot battery, character bonuses |
| Generated recipe productivity | Yes | engines, circuits, science packs, modded visible recipes |
| Event-driven scripted research | Yes, carefully | spoilage preservation, agricultural growth speed |
| Small megabase unlocks | Maybe | high-throughput pump, only if optional and tightly scoped |
| Startup prototype settings | Maybe, disabled by default | pipeline extent multiplier |
| New production chains | Usually no | greenhouses, refrigeration, super-bacteria |
| Broad gameplay overhauls | No | cold chain, quality overhaul, space-platform overhaul |

A feature belongs in MIR only if at least one is true:

1. It uses a native Factorio technology modifier.
2. It is generated recipe productivity.
3. It is a bounded, event-driven scripted research effect.
4. It is a small optional unlock that directly supports megabase scaling and does not introduce a new gameplay loop.

Otherwise it should be deferred, documented only, rejected for now, or split into a companion mod.

## Release Buckets

Every candidate feature must be classified before implementation.

| Bucket | Meaning | Rule |
| --- | --- | --- |
| Ship | Implement for the named release | API path is known, bounded, testable, and in scope |
| Spike | Investigate with a throwaway save, fixture, or small prototype | API behavior, compatibility, UPS, or balance is uncertain |
| Defer | Keep in MIR backlog, not this release | Good fit but wrong timing |
| Companion | Belongs in a separate mod | Introduces a new gameplay loop or content system |
| Reject for now | Do not pursue without new API/supporting evidence | Too hacky, too broad, or UPS-hostile |

## v2.0.5 Target

Theme:

```text
Scripted research foundation + Space Age agriculture scaling.
```

v2.0.5 should ship only after the current scripted slice is proven in real saves.

### v2.0.5 Ship

| Feature | Status | Implementation | Release requirement |
| --- | --- | --- | --- |
| Scripted-tech framework | Implemented, harden | `control.lua` plus manager/effect modules | No `on_tick`; load cleanly in fresh and upgraded saves |
| Spoilage preservation | Implemented, validate | `nothing` effect plus global spoil time modifier | Verify existing spoilable stack behavior, disabling, reversal, and multiple forces |
| Agricultural growth speed | Implemented, validate | `on_tower_planted_seed` plus `tick_grown` adjustment | Verify event behavior in-game and large farm performance |
| Electric shooting speed Tesla coverage | Implemented | `gun-speed` for `tesla` and `electric` | Confirm generated tech affects Tesla turret category and keeps discharge defense coverage |
| Vanilla Space Age productivity skip | Implemented | data-stage duplicate infinite recipe-productivity filter | Confirm LDS, plastic, processing unit, and rocket fuel are skipped, not duplicated |
| Package parity | Implemented, repeat before release | build and validation scripts | Release zip includes control files and matches repo sources |
| Documentation refresh | In progress | README, roadmap, TODO, compatibility, test results, changelog | Docs reflect tested behavior, not assumptions |

### v2.0.5 Spike Only

These can be investigated during the v2.0.5 cycle, but should not delay the release unless they are already proven and tiny.

| Feature | Why spike only | Decision gate |
| --- | --- | --- |
| Settings presets | Useful UX, but changes many defaults | Ship only if behavior is explicit and does not surprise existing users |
| Agricultural yield | Balance-heavy and harvest-result behavior needs proof | Defer unless a no-scan event-only design is proven |
| Thruster fuel/oxidizer productivity | Clean in concept, but fluid recipe productivity needs validation | Add only if exact recipes and productivity behavior are proven |
| Oil processing productivity | Needs proof for fluid-output recipes | Add only if `change-recipe-productivity` behaves cleanly |
| High-throughput pump prototype | Clean prototype path, but broader than agriculture release | Defer to v2.1.0 unless deliberately pulled forward |
| Maraxis-like duplicate cargo tech detection | Compatibility-sensitive | Spike overlap detection before changing behavior |
| Krastorio 2 Spaced Out compatibility | Depends on current target compatibility | Test when available for this Factorio line |

### v2.0.5 Out Of Scope

- Refrigeration, freezers, CryoPants, and cold-chain logistics.
- Greenhouses and off-world Gleba farming.
- Super-bacteria ore production.
- Efficient or high-thrust thruster entities.
- True infinite thruster thrust research.
- Quality module odds research.
- Roboport range research or new roboport tiers.
- Runtime fluid, platform, module, or machine-behavior hacks.

## v2.0.5 Release Gates

v2.0.5 is releasable when all of these are true:

1. `scripts/Build-MIRPackage.ps1` succeeds and rebuilds `dist/more-infinite-research_2.0.5.zip`.
2. `scripts/Invoke-MIRValidation.ps1 -StaticOnly` succeeds.
3. `scripts/Invoke-MIRValidation.ps1 -FactorioBin "<factorio.exe>"` succeeds on Factorio 2.1.8+ with Space Age available.
4. A fresh Space Age save can research or force-complete spoilage preservation and agricultural growth speed.
5. An existing v2.0.0 MIR save upgrades to v2.0.5 without migration or control-stage errors.
6. Existing spoilable items on belts, in chests, in labs, in rockets, and on platforms are observed after spoilage preservation is researched.
7. Disabling spoilage preservation after use does not leave an unexplained permanent multiplier beyond the documented baseline limitation.
8. Research reversal and technology-effects reset recompute scripted effects correctly.
9. A multi-force save demonstrates the documented highest-level force behavior.
10. A large Gleba farm demonstrates agricultural growth handling without broad scans or visible performance issues.
11. Space Age vanilla infinite productivity technologies are not duplicated by MIR for LDS, plastic, processing units, or rocket fuel.
12. Changelog, README, compatibility docs, test results, and this roadmap are updated with measured results.

## v2.1.0 Target

Theme:

```text
Megabase logistics and compatibility expansion without turning MIR into a content overhaul.
```

v2.1.0 is the right place for features that are clean but broader than the v2.0.5 agriculture patch.

### v2.1.0 Candidates

| Feature | Bucket | Implementation type | Default | Notes |
| --- | --- | --- | --- | --- |
| High-throughput pump | Ship candidate | Prototype unlock | Optional/on if balanced | Replace the five-parallel-pumps pattern with a late-game expensive pump |
| Pipeline extent multiplier | Ship candidate | Startup prototype setting | Disabled | Megabase convenience, not research; compatibility-sensitive |
| Thruster fuel productivity | Ship candidate if proven | Recipe productivity | Enabled if recipe exists | Improves effective fuel economy without changing platform physics |
| Thruster oxidizer productivity | Ship candidate if proven | Recipe productivity | Enabled if recipe exists | Same as fuel productivity |
| Oil processing productivity | Spike to ship candidate | Recipe productivity | Off or conservative until proven | Validate fluid-only and mixed-output recipes first |
| Agricultural yield | Spike to defer/ship | Event-driven scripted effect | Disabled until proven | More balance-sensitive than growth speed |
| Settings presets | Ship candidate | Startup setting/default derivation | Conservative default | Presets: Vanilla-respectful, Megabase-balanced, Unlimited sandbox |
| Duplicate native modifier detection | Ship candidate | Data-stage overlap scan | Skip or warn by default | Relevant for cargo landing pad count and unloading distance |
| Maraxis compatibility pass | Ship candidate | Test/profile as needed | Opportunistic | Avoid dependency metadata unless required |
| Krastorio 2 Spaced Out compatibility pass | Ship candidate | Test/profile as needed | Opportunistic | Add profile only for concrete recipe/prototype gaps |
| Docs-generated stream catalog | Defer candidate | Scripted documentation helper | N/A | Useful for support, not gameplay |

### v2.1.0 Explicit Non-Goals

- No cold-chain system in the main mod.
- No greenhouse/off-world Gleba farming in the main mod.
- No new ore biology loop in the main mod.
- No quality overhaul in the main mod.
- No scripted platform-speed/thruster hack.
- No per-tick broad scans.

## Legacy v1.9.0 Backport Target

The next Factorio `2.0` legacy release should backport the finished v2.1.0 codebase, not reconstruct v2.0.0 or v2.0.5 commit-by-commit.

Backport rule:

```text
legacy = current MIR code, minus Factorio 2.1-only surface area, with Factorio 2.0 metadata and validation.
```

The legacy target version is:

```text
v2.1.0 on Factorio 2.1.x -> v1.9.0 on Factorio 2.0.x
```

The source of truth for the backport should be one exact v2.1.0 release commit, tag, or release branch. Do not begin the legacy port until v2.1.0 is stable enough that the snapshot is worth supporting.

Expected legacy-port shape:

- Start from `legacy`.
- Merge or snapshot the v2.1.0 source point into a temporary backport branch.
- Prefer v2.1.0 source code for shared generator, diagnostics, recipe matching, science-pack handling, compatibility cleanup, locale, docs structure, and validation infrastructure.
- Restore Factorio `2.0` release metadata.
- Remove or guard Factorio `2.1`-only features.
- Validate against a Factorio `2.0.x` binary before publishing.

Known or likely legacy-specific removals/guards:

| Surface | Legacy rule |
| --- | --- |
| `max-cargo-bay-unloading-distance` | Remove from legacy unless Factorio 2.0 validation proves support |
| `cargo-landing-pad-count` | Remove from legacy unless Factorio 2.0 validation proves support |
| Agricultural tower scripted events | Keep only if Factorio 2.0 exposes the required events and entity fields |
| Pipeline extent setting | Keep only if the same prototype fields exist and validation passes |
| High-throughput pump | Keep only if the pump prototype path validates under Factorio 2.0 |
| New v2.1.0 recipe-productivity streams | Keep if exact recipes exist and no duplicate infinite technology owns them |

Expected legacy-specific files:

- `info.json`
- `changelog.txt`
- `README.md`
- `docs/compatibility.md`
- `docs/roadmap.md`
- `docs/todo.md`
- `scripts/Invoke-MIRValidation.ps1`
- `prototypes/streams/direct-effects.lua`
- `dist/more-infinite-research_1.9.0.zip`

The success criterion is that the diff from v2.1.0 to legacy is mostly metadata, docs, validation branching, and explicit removal of Factorio `2.1`-only technology surfaces.

## Companion Mod Backlog

These ideas are worth keeping, but not as core MIR features.

| Companion idea | Scope |
| --- | --- |
| Cold Chain / CryoPants | freezer chest, freeze/thaw recipes, cold transport, freshness penalties |
| Advanced Agriculture | greenhouses, off-world fruit, artificial soil loops, heating constraints |
| More Infinite Logistics | high-throughput pumps, pipeline settings, maybe logistics entity tiers if they outgrow MIR |
| Advanced Quality Research | module tiers, quality odds tuning, quality-based spoilage rules |
| Space Platform Engines | efficient/high-thrust thrusters and platform logistics entities |
| Bio Resource Experiments | super-bacteria, biter egg accelerators, unusual spoilage challenges |

## Compatibility Policy

- Prefer prototype discovery and safe skipping over optional third-party dependencies.
- Add mod-specific profiles only when a known mod exposes concrete recipes/prototypes that generic matching misses.
- Do not delete another mod's finite progression chain unless a compatibility profile explicitly models that chain.
- If another mod already owns an infinite technology for the same recipe productivity or native modifier, MIR should skip, warn, or require an explicit opt-in setting before overlapping.
- Keep generated technology names stable unless a migration is written and tested.

## Performance Policy

Default MIR behavior must avoid broad runtime scanning.

Allowed:

- Data-stage scans of prototypes.
- Research-finish/reversal recomputation.
- Event-driven handling for a specific entity or event payload.
- Bounded scans only when the maximum scope is known and documented.

Not allowed for normal enabled-by-default features:

- `on_tick` scans of inventories, belts, containers, item stacks, surfaces, or all entities.
- Runtime mutation that pretends to be a native modifier when the engine does not expose one.
- Scripted fluid production, scripted platform speed, or scripted quality odds as a substitute for prototype support.

Any feature that needs active broad scanning must be disabled by default, marked experimental, deferred, or moved to a companion mod.

## API Proof Points To Keep Current

When changing these features, re-check official Factorio docs and local prototype IDs:

- `gun-speed` uses `ammo_category`; Tesla weapons use `tesla`, discharge defense uses `electric`.
- `change-recipe-productivity` uses exact recipe IDs; vanilla Space Age already owns LDS, plastic, processing unit, and rocket fuel productivity chains.
- `nothing` technology effects are the UI carrier for scripted technologies.
- `DifficultySettings.spoil_time_modifier` is global, writable, and bounded.
- Agricultural tower planting and `LuaEntity.tick_grown` are the event-driven basis for growth speed.
- `PumpPrototype.pumping_speed` is the prototype path for a high-throughput pump.
- `FluidBox.max_pipeline_extent` is prototype-stage behavior, not a runtime research modifier.
- Thruster performance is prototype-defined, so true infinite thrust research remains a poor fit unless the API changes.

## Release Order

Recommended order from here:

1. Finish v2.0.5 manual save validation.
2. Patch any v2.0.5 scripted-tech bugs found by gameplay testing.
3. Cut v2.0.5 as the focused agriculture/scripted-tech release.
4. Create v2.1.0 spikes for pump, pipeline extent, thruster fuel/oxidizer productivity, oil productivity, presets, and overlap detection.
5. Ship v2.1.0 with only the spikes that prove clean, bounded, and compatible.
6. Backport v2.1.0 to Factorio 2.0 as v1.9.0.
