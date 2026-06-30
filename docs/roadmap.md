# M.I.R. Roadmap

Updated: 2026-07-01

This is the current release roadmap for More Infinite Research after the v2.0.0 Factorio 2.1 compatibility release.

Use this document for release intent and scope. Use `docs/todo.md` for the executable checklist. Use `docs/post-2.0-feature-plan.md` for the long-form feedback archive and API notes behind these decisions.

## Current Baseline

The current development branch contains the first scripted runtime implementation slice that was originally staged under `2.0.5`. The release plan now treats that runtime work as **v2.1.0-bound** unless it receives the full manual save validation required for a runtime feature release.

The clean public release sequence is:

| MIR release | Factorio line | Release kind | Scope |
| --- | --- | --- | --- |
| `2.0.5` | `2.1.x` | Stabilization | documentation, package parity, validation hardening, compatibility wording |
| `2.1.0` | `2.1.x` | Runtime feature release | settings presets, scripted-tech framework, spoilage preservation, agricultural growth speed |
| `1.9.0` | `2.0.x` | Legacy port | compatible subset of the tested v2.1.0 snapshot |

Current dev already has useful v2.1.0-bound work:

- A narrow `control.lua` runtime surface for bounded scripted technologies.
- `control/scripted-techs.lua` for init, configuration change, research finish, research reversal, technology-effects reset, and agricultural tower planting handlers.
- Scripted spoilage preservation research using a visible `nothing` effect and the global spoil time modifier.
- Scripted agricultural growth speed research using agricultural tower planting events and plant `tick_grown`.
- Electric shooting speed coverage for both `tesla` and `electric` ammo categories, so Tesla guns, Tesla turrets, and discharge-defense-style equipment are all covered where the categories exist.
- Recipe-productivity duplicate prevention for recipes already owned by another infinite recipe-productivity technology.
- Space Age vanilla productivity technologies remain authoritative for processing units, low density structures, plastic, and rocket fuel instead of receiving parallel MIR technologies.
- Package and validation script coverage for `control.lua`, the control module tree, Tesla speed assertions, vanilla Space Age productivity skip assertions, branch-aware legacy checks, and the no-`on_tick` runtime guard.

Do not publish runtime feature claims from this branch until the v2.1.0 acceptance criteria are satisfied.

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

## Feature State Table

This table is the canonical current synthesis from the Reddit discussion and follow-up planning.

| Feature | State | Target |
| --- | --- | --- |
| Settings presets | Ship | `v2.1.0` |
| Scripted-tech framework | Ship after manual validation | `v2.1.0` |
| Spoilage preservation | Ship after manual validation | `v2.1.0` |
| Agricultural growth speed | Ship after manual validation | `v2.1.0` |
| Agricultural yield / fruit yield | Spike | `v2.1.x` |
| High-throughput pump / Der Pump | Spike or optional prototype unlock | `v2.1.x` |
| Pipeline extent setting | Spike; startup setting only | `v2.1.x` |
| Thruster fuel/oxidizer productivity | Spike recipe productivity | `v2.1.x` |
| True thruster thrust research | Reject for core MIR unless API changes | Later / companion |
| Engine/electric-engine productivity | Ship/verify | `v2.1.0` or `v2.1.x` |
| Oil processing productivity | Spike | `v2.1.x` |
| Quality module odds research | Spike/defer | Later |
| Robot battery/carrying capacity | Existing core | Existing |
| Roboport range | Spike/defer | Later |
| Refrigeration / CryoPants | Companion | Separate |
| Greenhouses / off-world Gleba | Companion | Separate |
| Super-bacteria | Companion | Separate |
| Biter egg chaos | Companion/experimental | Separate |

## v2.0.5 Target

Theme:

```text
Stabilization, docs, package parity, and validation hardening.
```

v2.0.5 should not be the agriculture runtime release. If v2.0.5 is published, keep it as a low-risk stabilization release and avoid runtime feature claims that have not been manually validated.

### v2.0.5 Ship

- Roadmap, TODO, compatibility, API proof, and manual-test documentation.
- Package validation requiring the current docs.
- Branch-aware validation for future Factorio `2.0` legacy metadata.
- Static no-`on_tick` runtime guard.
- Zip/source/docs/locale/package parity.
- README/mod-portal compatibility wording for Factorio `2.1.x` main and future Factorio `2.0.x` legacy.
- Changelog clarity for the actual release scope.

### v2.0.5 Acceptance Criteria

- Static validation passes.
- Package validation passes.
- `docs/todo.md`, `docs/api-proof-points.md`, and `docs/manual-test-plan.md` are included in the package.
- README, docs, changelog, and packaged zip agree on release scope.
- No unvalidated runtime feature claims are made.
- `dist/<mod-name>_<version>.zip` is rebuilt from the committed source.
- `git status --short --branch`, `git log --oneline --decorate --graph --max-count=8`, and `git branch -vv` are checked before push/tag.

### v2.0.5 Out Of Scope

- Scripted-tech framework as a public feature.
- Spoilage preservation as a public feature.
- Agricultural growth speed as a public feature.
- Settings presets if they change runtime/default behavior.
- Refrigeration, freezers, CryoPants, and cold-chain logistics.
- Greenhouses and off-world Gleba farming.
- Super-bacteria ore production.
- Efficient or high-thrust thruster entities.
- True infinite thruster thrust research.
- Quality module odds research.
- Roboport range research or new roboport tiers.
- Runtime fluid, platform, module, or machine-behavior hacks.

## v2.1.0 Target

Theme:

```text
Scripted research foundation + Space Age agriculture/spoilage scaling.
```

v2.1.0 should be the first post-v2.0 runtime feature release. It can include already-started scripted code only after manual save validation proves the behavior and limitations.

### v2.1.0 Ship

| Feature | Bucket | Implementation type | Default | Notes |
| --- | --- | --- | --- | --- |
| Settings presets | Ship | Startup setting/default derivation | Conservative default | Presets: Vanilla-respectful, Megabase-balanced, Unlimited sandbox |
| Scripted-tech framework | Ship after validation | Event-driven runtime manager | Enabled only for supported features | No broad scans or `on_tick` |
| Spoilage preservation | Ship after validation | Global scripted effect using `spoil_time_modifier` | Preset-dependent | Global map effect; existing stack behavior must be documented |
| Agricultural growth speed | Ship after validation | `on_tower_planted_seed` plus `tick_grown` | Preset-dependent | New plants first; existing plant rescale only if bounded and proven |
| Scripted-tech diagnostics | Ship | Runtime/debug diagnostics | Off by default | Must explain recomputation and unsupported states |
| Engine/electric-engine productivity verification | Ship/verify | Recipe productivity | Existing defaults | Confirm current coverage and duplicate behavior |
| Compatibility docs and test results | Ship | Docs/evidence | N/A | Manual save results are release-blocking |

### v2.1.x Spike Queue

| Feature | State | Notes |
| --- | --- | --- |
| Agricultural yield | Spike | Harvest behavior and balance need proof |
| High-throughput pump / Der Pump | Spike or optional prototype unlock | Good candidate, not a v2.1.0 blocker |
| Pipeline extent setting | Spike; startup setting only | Prototype-stage behavior, not research |
| Thruster fuel/oxidizer productivity | Spike | Requires recipe-productivity proof for fluid recipes |
| Oil processing productivity | Spike | Do not promise fluid recipe productivity until tested |
| Quality module odds | Spike/defer | No known native force modifier |
| Roboport range | Spike/defer | Prefer prototype tier/startup setting if no native modifier |
| Duplicate native modifier detection | Spike/ship if small | Useful for cargo and mod overlap |
| Maraxis/Krastorio compatibility pass | Spike/ship if available | Opportunistic profiles only for concrete gaps |

### v2.1.0 Acceptance Criteria

- Fresh Space Age save loads and can research scripted technologies.
- Existing v2.0.x save upgrades without migration/control errors.
- Spoilage preservation behavior is measured for newly created spoilable items.
- Spoilage preservation behavior is measured for existing items on belts, in chests, in labs, in rockets/platform inventories, and in partially spoiled stacks.
- Changelog plainly states whether existing stacks are affected or keep current spoil deadlines.
- Research finish, research reversal, technology-effects reset, init, and configuration changes recompute scripted effects correctly.
- Multi-force behavior is tested and documented.
- Feature disable/re-enable behavior is tested and documented.
- Agricultural growth speed works for newly planted tower crops.
- Existing tower-owned plants are either safely rescaled through bounded/deduplicated handling or explicitly documented as not rescaled.
- No broad `on_tick` scanning exists.
- Runtime and manual validation results are recorded in `docs/test-results.md`.
- Stable generated technology IDs are preserved or migrations are documented.

### v2.1.0 Explicit Non-Goals

- No cold-chain system in the main mod.
- No greenhouse/off-world Gleba farming in the main mod.
- No new ore biology loop in the main mod.
- No quality overhaul in the main mod.
- No scripted platform-speed/thruster hack.
- No per-tick broad scans.

## Legacy v1.9.0 Backport Target

The next Factorio `2.0` legacy release should backport the finished More Infinite Research v2.1.0 codebase, not reconstruct v2.0.0 or v2.0.5 commit-by-commit.

| MIR release | Factorio line | Branch | Role |
| --- | --- | --- | --- |
| `2.1.0` | `2.1.x` | `dev` / `main` | Source release snapshot |
| `1.9.0` | `2.0.x` | `legacy` | Compatibility port of the source snapshot |

Backport rule:

```text
legacy = current MIR code, minus Factorio 2.1-only surface area, with Factorio 2.0 metadata and validation.
```

The legacy target version is:

```text
More Infinite Research v2.1.0 on Factorio 2.1.x -> More Infinite Research v1.9.0 on Factorio 2.0.x
```

The source of truth for the backport should be one exact v2.1.0 release commit, tag, or release branch. Do not begin the legacy port until v2.1.0 is stable enough that the snapshot is worth supporting.

Recommended setup:

```powershell
git fetch origin
git checkout -b backport/legacy-1.9.0 origin/legacy
git merge --no-ff --no-commit v2.1.0
```

If the release is identified by commit instead of tag:

```powershell
git merge --no-ff --no-commit <v2.1.0-release-commit>
```

Do not cherry-pick a guessed subset unless the merge strategy fails and the fallback plan is documented.

Expected legacy-port shape:

- Start from `legacy`.
- Merge or snapshot the v2.1.0 source point into a temporary backport branch.
- Prefer v2.1.0 source code for shared generator, diagnostics, recipe matching, science-pack handling, compatibility cleanup, locale, docs structure, and validation infrastructure.
- Restore Factorio `2.0` release metadata.
- Remove or guard Factorio `2.1`-only features.
- Validate against a Factorio `2.0.x` binary before publishing.

Legacy `info.json` target:

```json
{
  "version": "1.9.0",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0",
    "? space-age"
  ]
}
```

Legacy must not carry these Factorio `2.1` dependency floors unless later Factorio `2.0` validation proves a specific ordering need:

- `base >= 2.1.x`
- `? elevated-rails >= 2.1.x`
- `? recycler >= 2.1.x`
- `? quality >= 2.1.x`
- `? space-age >= 2.1.x`

Known or likely legacy-specific removals/guards:

| Surface | Legacy rule |
| --- | --- |
| `research_cargo_bay_unloading_distance` | Remove from legacy unless Factorio 2.0 validation proves support |
| `research_cargo_landing_pad_count` | Remove from legacy unless Factorio 2.0 validation proves support |
| `max-cargo-bay-unloading-distance` | Must not appear in legacy direct-effect stream definitions unless support is proven |
| `cargo-landing-pad-count` | Must not appear in legacy direct-effect stream definitions unless support is proven |
| Agricultural tower scripted events | Keep only if Factorio 2.0 exposes the required events and entity fields |
| Pipeline extent setting | Keep only if the same prototype fields exist and validation passes |
| High-throughput pump | Keep only if the pump prototype path validates under Factorio 2.0 |
| New v2.1.0 recipe-productivity streams | Keep if exact recipes exist and no duplicate infinite technology owns them |

Keep from the v2.1.0 source snapshot unless Factorio `2.0` validation proves a specific incompatibility:

- `data-final-fixes.lua` generation.
- lab-input science-pack discovery.
- lab incompatibility policy.
- science-pack ingredient policy.
- recipe matching refactor.
- diagnostics and recipe-match diagnostics.
- base-tech extension safety.
- opportunistic compatibility cleanup.
- validation and package parity tooling.
- docs and locale structure.

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

Static validation is already branch-aware from `info.json`: Factorio `2.0` metadata rejects Factorio `2.1` dependency floors and fails if legacy direct-effect stream definitions still contain `max-cargo-bay-unloading-distance` or `cargo-landing-pad-count`.

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

The detailed proof ledger and unknowns are maintained in `docs/api-proof-points.md`. Named manual save scenarios are maintained in `docs/manual-test-plan.md`.

## Release Order

Recommended order from here:

1. Keep `dev` state unambiguous with `git status`, `git log --oneline --decorate --graph --max-count=8`, and `git branch -vv` before pushing or tagging.
2. If publishing v2.0.5, keep it as a stabilization/docs/package-parity release and avoid unvalidated runtime feature claims.
3. Treat the current scripted runtime implementation as v2.1.0-bound work until manual save validation is complete.
4. Ship v2.1.0 as the scripted agriculture/spoilage and settings-preset release.
5. Continue pump, pipeline, thruster fuel/oxidizer, oil productivity, quality odds, and roboport range as v2.1.x spikes.
6. Backport the tested v2.1.0 snapshot to Factorio 2.0 as v1.9.0.
