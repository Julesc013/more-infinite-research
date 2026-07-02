# M.I.R. Roadmap

Updated: 2026-07-01

This is the current release roadmap for More Infinite Research after the v2.0.0 Factorio 2.1 compatibility release.

Use this document for release intent and scope. Use `docs/todo.md` for the executable checklist, `docs/release-plan-2.1.0.md` for the next release-gated implementation plan, and `docs/post-2.0-feature-plan.md` for the long-form feedback archive and API notes behind these decisions.

## Release Cadence

The release model is:

```text
patch .5 releases = quick, low-risk implementation and feedback releases
minor .0 releases = larger feature waves
legacy 1.9.x releases = Factorio 2.0 compatibility ports of tested current-line snapshots
```

`v2.0.5` is **not** docs-only. It is the first quick feedback release after `v2.0.0` and should include the easy, bounded, already-understood changes that are practical to drop into a mods folder and test now.

The minimum manual smoke checks gate the `v2.0.5` quick patch. The full scripted manual matrix gates default enablement and stronger public behavior claims for scripted candidates. If a candidate fails proof or grows beyond the quick-patch scope, that default, claim, or feature moves to `v2.1.0`; the whole release does not become docs-only.

| MIR release | Factorio line | Release kind | Scope |
| --- | --- | --- | --- |
| `2.0.5` | `2.1.x` | Quick feedback patch | small/easy fixes, default-off scripted agriculture/spoilage candidates, docs, validation, package parity |
| `1.9.0` | `2.0.x` | Legacy port | compatible subset of the tested `2.0.5` quick-patch snapshot |
| `2.1.0` | `2.1.x` | Larger feature wave | settings presets, harder compatibility work, pump/fluid/logistics spikes that graduate, broader scripted refinements |
| `2.1.5` | `2.1.x` | Quick feedback patch | small fixes and feedback from `2.1.0` |
| `1.9.5` | `2.0.x` | Legacy port | compatible subset of the tested `2.1.5` snapshot |
| `2.2.0` | `2.1.x` | Larger feature wave | next larger batch after the `2.1.x` feedback cycle |
| `1.9.9` | `2.0.x` | Final legacy port | final Factorio 2.0 port from the latest tested `2.x.x` current-line release when Factorio 2.1 becomes stable or another verified upstream cutoff is chosen |

The `1.9.9` cutoff should be treated as a release trigger, not an API assumption. When planning the final legacy port, verify the actual Factorio 2.1 stable status and the exact latest MIR `2.x.x` source point.

## Current Baseline

Current `dev` already has the intended `v2.0.5` quick-patch candidate work:

- A narrow `control.lua` runtime surface for bounded scripted technologies.
- `control/scripted-techs.lua` for init, configuration change, research finish, research reversal, technology-effects reset, and agricultural tower planting handlers.
- Scripted spoilage preservation research using a visible `nothing` effect and the global spoil time modifier.
- Scripted agricultural growth speed research using agricultural tower planting events and plant `tick_grown`.
- Electric shooting speed coverage for both `tesla` and `electric` ammo categories, so Tesla guns, Tesla turrets, and discharge-defense-style equipment are all covered where the categories exist.
- Electric Shooting Speed uses the Space Age electric-weapons-damage texture when that technology exists, with a discharge defense fallback for vanilla/no-Space-Age games.
- Recipe-productivity duplicate prevention for recipes already owned by another infinite recipe-productivity technology.
- Space Age vanilla productivity technologies remain authoritative for processing units, low density structures, plastic, and rocket fuel instead of receiving parallel MIR technologies.
- Heavy ammunition productivity is presented as Cannon shell productivity while keeping the existing generated technology ID stable.
- Generated stream icons replace inherited vanilla constant badges with badges matching MIR's actual effect type.
- Package and validation script coverage for `control.lua`, the control module tree, Tesla speed assertions, broad generated-chain integrity, vanilla Space Age productivity skip assertions, branch-aware legacy checks, and the no-`on_tick` runtime guard.

The public release rule is:

```text
ship the easy v2.0.5 features that pass validation;
defer only the features that fail proof or become larger than a quick patch.
```

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
| Electric shooting speed Space Age icon, vanilla fallback, descriptions, and Tesla coverage | Ship | `v2.0.5` |
| Flamethrower/electric/Tesla shooting-speed locale fixes | Ship | `v2.0.5` |
| Hidden Quality load ordering for module productivity | Ship | `v2.0.5` |
| Omega Drill style mining drill productivity matching | Ship | `v2.0.5` |
| Weapon shooting speed finite vanilla bonus preservation | Ship | `v2.0.5` |
| Vanilla Space Age productivity duplicate skip | Ship | `v2.0.5` |
| Scripted-tech framework | Ship default-off candidate | `v2.0.5` |
| Spoilage preservation | Ship default-off experimental candidate; default-on later if proved | `v2.0.5` / `v2.1.x` |
| Agricultural growth speed for newly planted tower crops | Ship default-off experimental candidate; default-on later if proved | `v2.0.5` / `v2.1.x` |
| Duplicate native modifier diagnostics for cargo/logistics overlap | Ship diagnostic-only | `v2.0.5` |
| Scripted diagnostics/docs/package validation | Ship | `v2.0.5` |
| Settings confidence pass: clearer labels, ordering, warnings, dropdown help, and docs | Ship | `v2.0.5` |
| Cannon shell productivity rename/icon and generated badge audit | Ship | `v2.0.5` |
| Engine/electric-engine productivity verification | Ship/verify | `v2.0.5` |
| Settings presets with real mode/override behavior | Started | `v2.1.0` |
| Existing agricultural plant rescale | Spike/ship if bounded | `v2.1.0` |
| Agricultural yield / fruit yield | Spike | `v2.1.0` or later |
| High-throughput pump / Der Pump | Spike or optional prototype unlock | `v2.1.0` |
| Pipeline extent setting | Spike; startup setting only | `v2.1.0` |
| Thruster fuel/oxidizer productivity | Spike recipe productivity | `v2.1.0` or `v2.1.5` |
| True thruster thrust research | Reject for core MIR unless API changes | Later / companion |
| Oil processing productivity | Spike | `v2.1.x` |
| Quality module enrichment / quality odds research | Spike/defer; likely add-on or prototype-tier feature | Later |
| Robot battery/carrying capacity | Existing core | Existing |
| Roboport range | Spike/defer | Later |
| Refrigeration / CryoPants | Companion | Separate |
| Greenhouses / off-world Gleba | Companion | Separate |
| Super-bacteria | Companion | Separate |
| Biter egg chaos | Companion/experimental | Separate |

## v2.0.5 Target

Theme:

```text
Quick, easy feedback patch for tested low-risk improvements.
```

`v2.0.5` should contain the small changes that are already implemented or straightforward to validate. It should not wait for the larger `v2.1.0` roadmap.

### v2.0.5 Ship

- Electric Shooting Speed corrected to cover `tesla` as well as `electric`.
- Discharge-defense-style `electric` category coverage retained.
- Electric Shooting Speed uses the Space Age electric-weapons-damage texture when available, while discharge defense remains the vanilla/no-Space-Age fallback and prerequisite anchor.
- Flamethrower, electric, and Tesla shooting-speed modifier descriptions supplied by MIR locale.
- Quality declared as a hidden optional load-order dependency so Quality module recipes are visible before module productivity generation.
- Mining drill productivity expanded to cover Omega Drill style and broader visible modded drill outputs.
- Weapon shooting speed overlap handling narrowed so finite vanilla rocket and cannon-shell speed bonuses remain intact.
- Recipe-productivity duplicate skipping so vanilla Space Age productivity chains stay authoritative.
- Processing unit, low density structure, plastic, and rocket fuel checks so MIR does not create parallel Space Age productivity techs for recipes already owned by vanilla infinite techs.
- Heavy ammunition productivity renamed to Cannon shell productivity without renaming the existing generated technology ID.
- Cannon shell productivity uses cannon shell item art and keeps shell/ammo coverage limited to ammo recipes, including artillery shell and railgun ammo.
- Generated MIR stream icon badges match effect type, including speed for Electric Shooting Speed even when it borrows electric-weapons-damage art.
- Scripted-tech framework if the manual save matrix passes.
- Spoilage preservation if newly created and existing-stack behavior is tested and documented.
- Agricultural growth speed for newly planted agricultural tower crops if the event path is manually verified.
- Settings confidence pass with clearer startup-setting names, tooltips, dropdown option descriptions, category ordering, and default-off warnings for experimental/sandbox features.
- Documentation, API proof ledger, manual test plan, validation hardening, and rebuilt package parity.

### v2.0.5 Acceptance Criteria

- Static validation passes.
- Runtime fixture validation passes on the supported Factorio `2.1.x` binary.
- Package validation passes.
- The current `docs/` tree is included in the package and package parity follows the current documentation layout.
- README, docs, changelog, and packaged zip agree on the actual shipped features.
- Manual results exist for the scripted features that are claimed as shipped.
- If spoilage preservation only affects new stacks, the changelog says that plainly.
- If agricultural growth speed only affects newly planted crops, the changelog says that plainly.
- `dist/<mod-name>_<version>.zip` is rebuilt from the committed source.
- `git status --short --branch`, `git log --oneline --decorate --graph --max-count=8`, and `git branch -vv` are checked before push/tag.

### v2.0.5 Defer If Proof Fails

Only defer the specific feature that fails proof:

- Spoilage preservation moves to `v2.1.0` if existing-stack behavior, reversal, disabling, or multi-force behavior is unsafe or unclear.
- Agricultural growth speed moves to `v2.1.0` if the tower event path or `tick_grown` behavior is not stable in real saves.
- Existing plant rescale is not required for `v2.0.5`; keep it for `v2.1.0` unless it is clearly bounded and safe.
- Settings presets started on `dev` after `v2.0.5`: the first slice controls technology enablement through `Custom/manual`, `Vanilla-respectful`, `Megabase-balanced`, and `Unlimited sandbox`.
- Numeric preset defaults are intentionally not part of the first slice; cost, growth, max-level, and research-unit-time settings remain manual.
- Do not add real settings presets to `v2.0.5`; the quick patch only improves confidence in the existing settings.

## v1.9.0 Legacy Backport Released

Theme:

```text
Factorio 2.0 compatibility port of the tested v2.0.5 quick patch.
```

`v1.9.0` was released directly after `v2.0.5` instead of waiting for `v2.1.0`. This gives Factorio `2.0.x` players the Tesla/electric fixes, duplicate-productivity safety, validation hardening, and default-off scripted candidate framework where the Factorio `2.0` API supports it.

`v1.9.0` is still a compatibility subset, not full parity. The port removed the Factorio `2.1`-only cargo landing pad count and cargo bay unloading distance modifier streams.

Use the detailed rules in the Legacy Backport Strategy section below for future `v1.9.x` ports, but use the latest tested current-line source point for each future snapshot.

## v2.1.0 Target

Theme:

```text
User-facing control + compatibility discipline + proof-gated expansion.
```

`v2.1.0` is the next controlled feature wave. It should not absorb every good idea. The release must ship settings control, compatibility policy, and only the scripted/logistics/productivity work that passes proof.

The executable release gate lives in `docs/release-plan-2.1.0.md`.

### v2.1.0 Ship Candidates

| Feature | Bucket | Implementation type | Notes |
| --- | --- | --- | --- |
| Settings presets | Started | Startup setting/default derivation | Enablement presets implemented first; numeric preset defaults remain out of scope until explicitly designed |
| Preset override model | Started | Startup setting/default derivation | Per-technology enable policy supports Use settings mode, Force enabled, and Force disabled |
| Duplicate native modifier policy | Ship | Data-stage overlap scan plus explicit policy | Promote `v2.0.5` diagnostic-only reporting to skip/warn/prefer/allow behavior |
| Icon source resolver and asset policy | Ship | Data-stage icon candidate resolver plus package validation guard | Prefer loaded Space Age/Wube art when available; do not redistribute original Space Age files in MIR |
| Scripted-tech refinements | Ship if needed | Event-driven runtime manager | Improve storage/reversal/diagnostics after `v2.0.5` feedback |
| Existing agricultural plant rescale | Ship if bounded | Research-change bounded scan | Deduplicate tower-owned plants and avoid surface-wide scans |
| High-throughput pump / Der Pump | Ship if prototype proof passes | Prototype unlock | Good megabase QoL candidate |
| Pipeline extent setting | Ship if compatibility proof passes | Startup prototype setting | Disabled by default unless proven safe |
| Thruster fuel/oxidizer productivity | Ship if recipe proof passes | Recipe productivity | Do not add true thrust research |
| Oil/fluid recipe productivity | Spike/ship if proof passes | Recipe productivity | Needs in-game proof on fluid outputs |
| Compatibility docs and test results | Ship | Docs/evidence | Maraxis/Krastorio-style validation when available |

### v2.1.0 Acceptance Criteria

- Every shipped feature has a clear implementation type: native modifier, recipe productivity, scripted event, prototype unlock, or startup setting.
- No shipped feature uses broad `on_tick` scanning.
- Space Age technology art is referenced only when Space Age is loaded; base-only fallback icons use base, MIR-owned, or otherwise redistributable assets.
- Any deferred `v2.0.5` scripted feature has its unresolved blocker closed before being claimed.
- New prototype unlocks have recipe, power, balance, localization, and package tests.
- Startup prototype settings document why they cannot be runtime research.
- Recipe-productivity additions prove exact recipe IDs and no vanilla/other-mod infinite duplicate.
- README, roadmap, compatibility docs, test results, and changelog are updated before release.

## v2.1.5 Feedback Patch

Theme:

```text
Small fixes and feedback from v2.1.0.
```

Use `v2.1.5` the same way as `v2.0.5`: ship quick, bounded corrections and compatibility feedback without waiting for the next major feature wave.

Good `v2.1.5` work:

- Bug fixes from `v2.1.0`.
- Small compatibility profiles or duplicate-detection fixes.
- Recipe ID additions that are already proven.
- Locale/docs/validation updates.
- Minor balance adjustments for features already shipped in `v2.1.0`.

Do not use `v2.1.5` for new broad gameplay systems.

## v2.2.0 Target

Theme:

```text
Next larger feature wave after the v2.1.x feedback cycle.
```

Candidate work:

- Any pump/fluid/logistics work that was too large for `v2.1.0`.
- More advanced compatibility automation.
- Larger settings UX reorganization.
- Additional bounded scripted research if the framework has proven stable.
- Companion-mod split decisions for ideas that keep growing beyond MIR.

## Legacy Backport Strategy

Do not reconstruct older releases commit-by-commit for `legacy`. A legacy release should be the tested current-line source snapshot, minus unsupported Factorio `2.1` surface area, with Factorio `2.0` metadata and validation.

Backport mappings:

| Current MIR release | Factorio line | Legacy MIR release | Factorio line |
| --- | --- | --- | --- |
| `2.0.5` | `2.1.x` | `1.9.0` | `2.0.x` |
| `2.1.5` | `2.1.x` | `1.9.5` | `2.0.x` |
| latest tested `2.x.x` at the stable cutoff | `2.1.x` | `1.9.9` | `2.0.x` |

Backport rule:

```text
legacy = tested current MIR code, minus Factorio 2.1-only surface area,
with Factorio 2.0 metadata and validation.
```

Recommended setup for the first legacy port:

```powershell
git fetch origin
git checkout -b backport/legacy-1.9.0 origin/legacy
git merge --no-ff --no-commit v2.0.5
```

If the source is identified by commit instead of tag:

```powershell
git merge --no-ff --no-commit <v2.0.5-release-commit>
```

Expected legacy-port shape:

- Start from `legacy`.
- Merge or snapshot the tested current-line source point into a temporary backport branch.
- Prefer current-line source code for shared generator, diagnostics, recipe matching, science-pack handling, compatibility cleanup, locale, docs structure, and validation infrastructure.
- Restore Factorio `2.0` release metadata.
- Remove or guard Factorio `2.1`-only features.
- Validate against a Factorio `2.0.x` binary before publishing.

Legacy `info.json` target for `1.9.0`:

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
| New recipe-productivity streams | Keep if exact recipes exist and no duplicate infinite technology owns them |

Keep from the source snapshot unless Factorio `2.0` validation proves a specific incompatibility:

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

Static validation is branch-aware from `info.json`: Factorio `2.0` metadata rejects Factorio `2.1` dependency floors and fails if legacy direct-effect stream definitions still contain `max-cargo-bay-unloading-distance` or `cargo-landing-pad-count`.

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
- `change-recipe-productivity` uses exact recipe IDs; vanilla Space Age already owns LDS, plastic, processing unit, and rocket fuel productivity chains, and MIR validation must prove there is only one infinite owner per recipe.
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
2. Finish `v2.0.5` as the quick/easy implementation patch: Tesla fix, duplicate-productivity prevention, default-off scripted agriculture/spoilage candidates, docs, validation, and package parity.
3. `v1.9.0` has been released from `legacy` as the tested `v2.0.5` snapshot backport to Factorio 2.0.
4. Move only failed or too-large `v2.0.5` candidates to `v2.1.0`.
5. Ship `v2.1.0` as the larger feature wave.
6. Ship quick `v2.1.5` feedback fixes.
7. Backport the tested `v2.1.5` snapshot as `v1.9.5`.
8. Ship the next larger wave as `v2.2.0`.
9. When Factorio 2.1 becomes stable or another verified upstream cutoff is chosen, backport the latest tested MIR `2.x.x` release as final Factorio 2.0 build `v1.9.9`.
