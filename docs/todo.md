# M.I.R. TODO

Updated: 2026-07-01

This is the executable task list for the next More Infinite Research releases.

Use `docs/roadmap.md` for release scope and product boundaries. Use `docs/post-2.0-feature-plan.md` for the deeper idea archive.

## Working Rules

- Target `dev` for active Factorio `2.1` development.
- Keep v2.0.5 narrow: stabilization, docs, package parity, validation hardening, and compatibility wording.
- Treat scripted-tech framework, spoilage preservation, agricultural growth speed, and settings presets as v2.1.0-bound unless a separate release decision promotes them after manual validation.
- Keep generated technology names stable unless a tested migration exists.
- Prefer native modifiers and recipe productivity.
- Scripted effects must be event-driven, bounded, reversible where practical, and documented.
- Do not add broad `on_tick` scans for inventories, belts, containers, item stacks, surfaces, or all entities.
- Commit documentation and implementation changes at the end of each completed work turn.

## Immediate Status

Done in the current development branch:

- [x] Bump mod metadata to `2.0.5`.
- [x] Add `control.lua`.
- [x] Add scripted-tech manager under `control/scripted-techs.lua`.
- [x] Add spoilage preservation scripted effect.
- [x] Add agricultural growth speed scripted effect.
- [x] Add visible `nothing` effects for scripted technologies.
- [x] Add settings/defaults for the two scripted streams.
- [x] Add runtime scripted-effect debug setting.
- [x] Fix Electric Shooting Speed to include `tesla` ammo category.
- [x] Keep `electric` ammo category coverage for discharge defense.
- [x] Detect and skip recipe productivity already owned by another infinite recipe-productivity technology.
- [x] Confirm Space Age vanilla owns processing unit, low density structure, plastic, and rocket fuel infinite productivity chains.
- [x] Rebuild `dist/more-infinite-research_2.0.5.zip`.
- [x] Run static/package/runtime fixture validation on Factorio 2.1.8.
- [x] Add branch-aware legacy validation guardrails.
- [x] Add static no-`on_tick` validation guard.

Important release note: the scripted runtime work above is implemented in `dev`, but the public release plan now treats it as **v2.1.0-bound** until the manual runtime validation matrix is complete.

## v2.0.5 Stabilization Release

These must be complete before publishing v2.0.5 as a stabilization/docs/package-parity release.

### v2.0.5 Acceptance Criteria

- [ ] Static validation passes.
- [ ] Package validation passes.
- [ ] `docs/todo.md` is included in the package.
- [ ] `docs/api-proof-points.md` is included in the package.
- [ ] `docs/manual-test-plan.md` is included in the package.
- [ ] README, docs, changelog, and package agree on release scope.
- [ ] No runtime feature claims are made without runtime/manual validation.
- [ ] `dist/more-infinite-research_2.0.5.zip` is rebuilt from committed source.
- [ ] Changelog has an entry matching `info.json` version.
- [ ] Zip filename and internal `info.json` version match `info.json`.
- [ ] Zip excludes dev-only files and includes required docs/source/locale/control files.
- [ ] Git tree is clean after build.

### API And ID Verification

- [x] Confirm Tesla gun, Tesla ammo, and Tesla turret use `ammo_category = "tesla"` in installed Space Age prototypes.
- [x] Confirm discharge defense uses `ammo_category = "electric"` in base prototypes.
- [x] Confirm `gun-speed` modifier is keyed by ammo category.
- [x] Confirm vanilla Space Age `processing-unit-productivity` owns `processing-unit`.
- [x] Confirm vanilla Space Age `low-density-structure-productivity` owns `low-density-structure` and `casting-low-density-structure`.
- [x] Confirm vanilla Space Age `plastic-bar-productivity` owns `plastic-bar` and `bioplastic`.
- [x] Confirm vanilla Space Age `rocket-fuel-productivity` owns `rocket-fuel`, `rocket-fuel-from-jelly`, and `ammonia-rocket-fuel`.
- [ ] Re-check official API docs before release if Factorio updates past the local validation version.

### Branch-State Check Before Push/Tag

- [ ] Run `git status --short --branch`.
- [ ] Run `git log --oneline --decorate --graph --max-count=8`.
- [ ] Run `git branch -vv`.
- [ ] Confirm the intended commits are reachable from `dev`.
- [ ] Confirm whether `dev` is ahead of `origin/dev` before pushing or tagging.

## v2.1.0 Runtime Release

These must be complete before publishing scripted-tech features.

### Scripted-Tech Framework

- [ ] Review `storage` layout for long-term stability and document every key in `docs/architecture.md`.
- [ ] Confirm spoilage baseline capture cannot compound MIR's own multiplier across load/configuration cycles.
- [ ] Decide whether research reversal should restore baseline immediately when no forces have levels.
- [ ] Confirm behavior when another mod also writes `game.difficulty_settings.spoil_time_modifier`.
- [ ] Store only MIR's own applied spoilage multiplier and remove/divide it out before recalculating when possible.
- [ ] Store last applied agricultural multiplier per force if existing plant rescale is implemented.
- [ ] Handle `on_init`.
- [ ] Handle `on_configuration_changed`.
- [ ] Handle `on_research_finished`.
- [ ] Handle `on_research_reversed`.
- [ ] Handle `on_technology_effects_reset`.
- [ ] Handle `on_runtime_mod_setting_changed` if runtime settings are introduced.
- [ ] Confirm static validation fails on accidental `on_tick` or `script.on_nth_tick`.

### Spoilage Preservation Manual Blockers

- [ ] Fresh Space Age save: confirm `research_spoilage_preservation` appears, researches, and displays the scripted effect text.
- [ ] Newly created spoilable items: confirm effect after `game.difficulty_settings.spoil_time_modifier` changes.
- [ ] Existing items on belts: document whether spoil deadlines change or remain fixed.
- [ ] Existing items in chests: document whether spoil deadlines change or remain fixed.
- [ ] Existing items in labs: document whether spoil deadlines change or remain fixed.
- [ ] Existing items in rocket/platform inventories: document whether spoil deadlines change or remain fixed.
- [ ] Existing partially spoiled stacks: document whether spoil deadlines change or remain fixed.
- [ ] Spoilage preservation reversal: research, apply, reverse, and confirm recomputation.
- [ ] Spoilage preservation disable path: disable the stream after it has been used and confirm documented baseline behavior.
- [ ] Spoilage preservation multi-force behavior: confirm highest non-enemy/non-neutral force level behavior.
- [ ] Changelog wording states the measured existing-stack behavior plainly.

### Agricultural Growth Speed Manual Blockers

- [ ] Fresh Space Age save: confirm `research_agricultural_growth_speed` appears, researches, and displays the scripted effect text.
- [ ] Agricultural tower event path: confirm a newly planted crop has its remaining growth time shortened.
- [ ] Agricultural growth cap: confirm extreme researched levels clamp to the documented `10x` cap.
- [ ] Existing tower-owned plants: decide whether they remain out of scope or are rescaled.
- [ ] If existing plant rescale is added, prove it is bounded and deduplicated.
- [ ] Large Gleba farm: test thousands of tower-owned plants and confirm no visible performance issue.
- [ ] No Space Age save: confirm scripted streams skip cleanly.

### Compatibility Validation

- [ ] Base game only.
- [ ] Elevated Rails only.
- [ ] Recycler only.
- [ ] Quality enabled with dependencies.
- [ ] Space Age enabled.
- [ ] Space Age with Quality disabled where Factorio permits it.
- [ ] Custom science pack fixture.
- [ ] Custom lab fixture.
- [ ] Late recipe fixture.
- [ ] Maraxis-like duplicate cargo landing pad technology fixture or manual test.
- [ ] Krastorio 2 Spaced Out test if compatible with the active Factorio line.
- [ ] Better Robots Extended smoke test.

### Documentation And Release Text

- [ ] Update `docs/test-results.md` with manual gameplay validation results.
- [ ] Update `docs/compatibility.md` with confirmed scripted-tech behavior.
- [ ] Update `docs/architecture.md` with final storage keys and event handlers.
- [ ] Update `README.md` for v2.1.0 behavior after testing.
- [ ] Finalize `changelog.txt` with measured caveats, not guesses.
- [ ] Add a mod portal/reddit release note that clearly says what is out of scope.
- [ ] Stable generated technology IDs are preserved or migrations are documented.
- [ ] Generate or record base + Space Age generated technology names and compare against the previous snapshot before release.

### Packaging

- [ ] Run `.\scripts\Build-MIRPackage.ps1`.
- [ ] Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- [ ] Run `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"`.
- [ ] Run `git diff --check`.
- [ ] Confirm `dist/<mod-name>_<version>.zip` has matching source/docs/locale parity.
- [ ] Confirm git tree is clean after final release commit.

## v2.1.0 Nice-To-Have, Do Not Block Release

- [ ] Add a small in-game diagnostics command or clearer debug log for current scripted multipliers.
- [ ] Add a one-page manual testing recipe for spoilage preservation and growth speed.
- [ ] Create a tiny test save specifically for scripted agriculture validation.

## v2.1.x Spike Queue

Do these only as bounded investigations. Do not merge into a feature release unless the result is clean, tested, and small.

| Spike | Question | Expected outcome |
| --- | --- | --- |
| Thruster fuel productivity | Does recipe productivity apply cleanly to `thruster-fuel` recipes? | Ship in v2.1.x if clean |
| Thruster oxidizer productivity | Does recipe productivity apply cleanly to `thruster-oxidizer` recipes? | Same as fuel |
| Oil processing productivity | Do fluid-only and mixed fluid recipes behave correctly with recipe productivity? | Ship later only with proof |
| Agricultural yield | Can harvest yield be changed with an event-only no-scan design? | Defer unless balance and event behavior are clean |
| High-throughput pump | Can a prototype unlock safely replace five parallel pumps? | v2.1.x candidate |
| Pipeline extent | Which fluidboxes need mutation and what compatibility risk exists? | v2.1.x candidate, disabled by default |
| Duplicate native modifiers | Can MIR detect overlapping infinite cargo/logistics technologies generically? | v2.1.x compatibility feature |
| Settings presets | Can presets be implemented without surprising existing configs? | v2.1.0 ship candidate |

## v2.1.0 Planned Work

v2.1.0 should be the first post-v2.0 runtime feature release.

### v2.1.0 Ship Candidates

- [ ] Settings presets: Vanilla-respectful, Megabase-balanced, Unlimited sandbox.
- [ ] Scripted-tech framework.
- [ ] Spoilage preservation after manual validation.
- [ ] Agricultural growth speed after manual validation.
- [ ] Scripted-tech diagnostics.
- [ ] Engine/electric-engine productivity verification.
- [ ] Compatibility docs and manual runtime test results.

### v2.1.0 Acceptance Criteria

- [ ] Every shipped v2.1.0 feature has a clear implementation type: native modifier, recipe productivity, scripted event, prototype unlock, or startup setting.
- [ ] No shipped v2.1.0 feature uses broad `on_tick` scanning.
- [ ] Existing spoilable-stack behavior is tested and documented.
- [ ] Every scripted feature documents storage keys, recomputation events, disable behavior, reversal behavior, and multi-force behavior.
- [ ] Any new recipe-productivity stream proves exact recipe IDs and no vanilla/other-mod infinite duplicate.
- [ ] Every startup prototype setting documents when it is applied and why it cannot be runtime research.
- [ ] Compatibility tests include no Space Age, Space Age, Space Age without Quality where supported, custom science/lab fixtures, and at least one large overhaul if available.
- [ ] README, roadmap, compatibility docs, test results, and changelog are updated before release.

## Legacy v1.9.0 Backport After v2.1.0

Do not reconstruct v2.0.0 or v2.0.5 commit-by-commit for `legacy`. The planned legacy release is More Infinite Research v1.9.0 for Factorio `2.0.x`, ported from the finished More Infinite Research v2.1.0 release commit for Factorio `2.1.x`.

### Backport Setup

- [ ] Finish and validate v2.1.0 on the Factorio `2.1` line.
- [ ] Tag or branch the exact v2.1.0 source point, or record the exact release commit hash.
- [ ] Run `git fetch origin`.
- [ ] Run `git checkout -b backport/legacy-1.9.0 origin/legacy`.
- [ ] Run `git merge --no-ff --no-commit v2.1.0`, or `git merge --no-ff --no-commit <v2.1.0-release-commit>` if using a commit hash.
- [ ] Do not cherry-pick a guessed subset unless the full snapshot merge fails and the fallback is documented.
- [ ] Prefer v2.1.0 source for shared generator, diagnostics, science-pack handling, recipe matching, compatibility cleanup, validation scripts, docs structure, and localization.
- [ ] Keep `data-final-fixes.lua` generation, lab-input science-pack discovery, lab incompatibility policy, science-pack ingredient policy, recipe matching, diagnostics, base-tech extension safety, opportunistic compatibility cleanup, validation/package parity tooling, docs structure, and locale structure unless Factorio `2.0` validation proves a specific incompatibility.

### Legacy Compatibility Patch

- [ ] Set `info.json` version to `1.9.0`.
- [ ] Set `info.json` `factorio_version` to `2.0`.
- [ ] Set `info.json` dependencies to the legacy target: `base >= 2.0` and `? space-age`.
- [ ] Remove `base >= 2.1.x` from legacy.
- [ ] Remove `? elevated-rails >= 2.1.x`, `? recycler >= 2.1.x`, `? quality >= 2.1.x`, and `? space-age >= 2.1.x` from legacy unless a specific Factorio `2.0` ordering need is proven.
- [ ] Remove or guard `research_cargo_bay_unloading_distance`.
- [ ] Remove or guard `research_cargo_landing_pad_count`.
- [ ] Confirm static validation fails if legacy direct-effect stream definitions still contain `max-cargo-bay-unloading-distance` or `cargo-landing-pad-count`.
- [ ] Verify whether agricultural tower events and `tick_grown` are available in the target Factorio `2.0.x` build before keeping scripted agriculture.
- [ ] Verify whether any v2.1.0 pump or pipeline prototype fields exist in Factorio `2.0.x` before keeping them.
- [ ] Rewrite `changelog.txt` as a `1.9.0` legacy backport entry, not a copied v2.1.0 entry.
- [ ] Update README and compatibility docs to state what is excluded from legacy.
- [ ] Build `dist/more-infinite-research_1.9.0.zip`.

### Legacy Validation

- [ ] Make `scripts/Invoke-MIRValidation.ps1` branch-aware from `info.json`.
- [ ] Static validation checks `factorio_version = "2.0"` on legacy.
- [ ] Static validation checks `base >= 2.0` style metadata on legacy.
- [ ] Static validation checks 2.1-only cargo modifiers are absent on legacy.
- [ ] Static validation skips 2.1-only cargo runtime fixture expectations on legacy.
- [ ] Run `.\scripts\Build-MIRPackage.ps1` on legacy.
- [ ] Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly` on legacy.
- [ ] Run `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Path\To\Factorio-2.0.x\bin\x64\factorio.exe"` on legacy.
- [ ] Do not validate the legacy port with the Steam-updated Factorio `2.1.x` binary.
- [ ] Fix failures in this order: load-time prototype errors, invalid modifiers/effects, metadata, unresearchable science packs, docs/package validation, locale synchronization.
- [ ] Keep the legacy diff small: metadata, docs, validation branching, package name, and explicit removal of Factorio `2.1`-only surfaces.

## Companion Mod Backlog

These are intentionally not v2.0.5 or v2.1.0 MIR core work.

- [ ] Cold Chain / CryoPants: freezer chest, freeze/thaw recipes, refrigerated transport, freshness penalty.
- [ ] Advanced Agriculture: greenhouse, off-world fruit, heating constraints, artificial soil loops.
- [ ] Advanced Quality Research: higher quality module tiers, quality odds tuning, quality-based spoilage.
- [ ] Space Platform Engines: efficient thruster, high-thrust thruster, related platform entities.
- [ ] Bio Resource Experiments: super-bacteria, biter egg accelerator, reverse spoilage challenges.
- [ ] More Infinite Logistics companion decision: split if pump/pipeline/entity unlocks grow beyond MIR's research-scaling identity.

## Rejected For Now

- [ ] True infinite thruster thrust research, unless Factorio exposes a native technology modifier.
- [ ] Runtime platform speed mutation as a fake thrust bonus.
- [ ] Infinite quality odds research through runtime module mutation.
- [ ] Refrigeration by scanning every spoilable stack in every inventory.
- [ ] Per-tick farm, belt, lab, container, platform, or item-stack scanning.

## Recurring Release Checklist

Run this before every release candidate:

- [ ] `git status --short --branch`
- [ ] `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes`
- [ ] `rg "on_tick" control prototypes`
- [ ] `rg "icon_mipmaps" prototypes`
- [ ] `.\scripts\Build-MIRPackage.ps1`
- [ ] `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`
- [ ] `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"`
- [ ] `git diff --check`
- [ ] Load the release zip from a normal Factorio mods folder.
- [ ] Record validation results in `docs/test-results.md`.
- [ ] Commit docs, code, changelog, and package together for the tested candidate.
