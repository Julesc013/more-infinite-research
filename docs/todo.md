# M.I.R. TODO

Updated: 2026-07-01

This is the executable task list for the next More Infinite Research releases.

Use `docs/roadmap.md` for release scope and product boundaries. Use `docs/post-2.0-feature-plan.md` for the deeper idea archive.

## Working Rules

- Target `dev` for active Factorio `2.1` development.
- Treat `.5` releases as quick feedback patches for small, bounded, tested changes.
- Treat `.0` releases as larger feature waves.
- Backport tested current-line snapshots to `legacy` as Factorio `2.0` compatible `1.9.x` releases.
- Do not rebuild `legacy` commit-by-commit from older releases.
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
- [x] Anchor Electric Shooting Speed to discharge defense for vanilla/no-Space-Age icon and prerequisite safety.
- [x] Add missing shooting-speed descriptions for flamethrower, electric, and Tesla modifiers.
- [x] Add hidden optional Quality load ordering for module productivity.
- [x] Add Omega Drill style mining drill productivity matching.
- [x] Detect and skip recipe productivity already owned by another infinite recipe-productivity technology.
- [x] Confirm Space Age vanilla owns processing unit, low density structure, plastic, and rocket fuel infinite productivity chains.
- [x] Rebuild `dist/more-infinite-research_2.0.5.zip`.
- [x] Run static/package/runtime fixture validation on Factorio 2.1.8.
- [x] Add branch-aware legacy validation guardrails.
- [x] Add static no-`on_tick` validation guard.

Important release note: the scripted runtime work above is a **v2.0.5 ship candidate**, not automatically deferred to `v2.1.0`. Ship the parts that pass manual proof. Defer only the specific feature or behavior that fails proof or becomes too large for a quick patch.

## v2.0.5 Quick Feedback Patch

`v2.0.5` should ship the easy and quick changes that are already implemented or simple to validate.

### v2.0.5 Ship Candidates

- [x] Electric Shooting Speed covers `tesla`.
- [x] Electric Shooting Speed still covers `electric`.
- [x] Electric Shooting Speed uses the vanilla discharge defense icon/prerequisite anchor when Space Age is absent.
- [x] Flamethrower and electric/Tesla shooting speed modifier descriptions are localized.
- [x] Quality is a hidden optional load-order dependency so module productivity can see quality module recipes.
- [x] Mining drill productivity covers Omega Drill style `omega-drill` and `omega-tau` recipes through validation fixtures.
- [x] Mining drill productivity covers broader visible modded `*-mining-drill` / `*-drill` outputs in the high-tier bucket.
- [x] Vanilla Space Age `processing-unit-productivity` remains authoritative.
- [x] Vanilla Space Age `low-density-structure-productivity` remains authoritative.
- [x] Vanilla Space Age `plastic-bar-productivity` remains authoritative.
- [x] Vanilla Space Age `rocket-fuel-productivity` remains authoritative.
- [x] Recipe productivity skips effects already owned by another infinite recipe-productivity technology.
- [x] Package includes `control.lua` and `control/`.
- [x] Package includes `docs/todo.md`, `docs/api-proof-points.md`, and `docs/manual-test-plan.md`.
- [ ] Spoilage preservation passes the manual blockers below.
- [ ] Agricultural growth speed for newly planted tower crops passes the manual blockers below.
- [ ] README/changelog state the exact measured behavior, especially for existing spoilable stacks and existing plants.

### v2.0.5 Acceptance Criteria

- [ ] Static validation passes.
- [ ] Package validation passes.
- [ ] Runtime fixture validation passes on the supported Factorio `2.1.x` binary.
- [ ] `docs/todo.md` is included in the package.
- [ ] `docs/api-proof-points.md` is included in the package.
- [ ] `docs/manual-test-plan.md` is included in the package.
- [ ] README, docs, changelog, and package agree on release scope.
- [ ] Runtime feature claims are backed by manual/runtime validation.
- [ ] `dist/more-infinite-research_2.0.5.zip` is rebuilt from committed source.
- [ ] Changelog has an entry matching `info.json` version.
- [ ] Zip filename and internal `info.json` version match `info.json`.
- [ ] Zip excludes dev-only files and includes required docs/source/locale/control files.
- [ ] Git tree is clean after build.

### v2.0.5 API And ID Verification

- [x] Confirm Tesla gun, Tesla ammo, and Tesla turret use `ammo_category = "tesla"` in installed Space Age prototypes.
- [x] Confirm discharge defense uses `ammo_category = "electric"` in base prototypes.
- [x] Confirm `gun-speed` modifier is keyed by ammo category.
- [x] Confirm current base/Space Age locale files do not provide all generated shooting-speed modifier descriptions MIR needs.
- [x] Confirm Factorio supports hidden optional dependencies through the `(?)` dependency prefix.
- [x] Confirm vanilla Space Age `processing-unit-productivity` owns `processing-unit`.
- [x] Confirm vanilla Space Age `low-density-structure-productivity` owns `low-density-structure` and `casting-low-density-structure`.
- [x] Confirm vanilla Space Age `plastic-bar-productivity` owns `plastic-bar` and `bioplastic`.
- [x] Confirm vanilla Space Age `rocket-fuel-productivity` owns `rocket-fuel`, `rocket-fuel-from-jelly`, and `ammonia-rocket-fuel`.
- [ ] Re-check official API docs before release if Factorio updates past the local validation version.

### v2.0.5 Scripted-Tech Framework

- [ ] Review `storage` layout for long-term stability and document every key in `docs/architecture.md`.
- [ ] Confirm spoilage baseline capture cannot compound MIR's own multiplier across load/configuration cycles.
- [ ] Decide whether research reversal should restore baseline immediately when no forces have levels.
- [ ] Confirm behavior when another mod also writes `game.difficulty_settings.spoil_time_modifier`.
- [ ] Store only MIR's own applied spoilage multiplier and remove/divide it out before recalculating when possible.
- [ ] Handle `on_init`.
- [ ] Handle `on_configuration_changed`.
- [ ] Handle `on_research_finished`.
- [ ] Handle `on_research_reversed`.
- [ ] Handle `on_technology_effects_reset`.
- [ ] Confirm static validation fails on accidental `on_tick` or `script.on_nth_tick`.

### v2.0.5 Spoilage Preservation Manual Blockers

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

### v2.0.5 Agricultural Growth Speed Manual Blockers

- [ ] Fresh Space Age save: confirm `research_agricultural_growth_speed` appears, researches, and displays the scripted effect text.
- [ ] Agricultural tower event path: confirm a newly planted crop has its remaining growth time shortened.
- [ ] Agricultural growth cap: confirm extreme researched levels clamp to the documented `10x` cap.
- [ ] Existing tower-owned plants remain out of scope for `v2.0.5`, unless a bounded/deduplicated rescale is proven small.
- [ ] Large Gleba farm: test many newly planted crops and confirm no visible performance issue.
- [ ] No Space Age save: confirm scripted streams skip cleanly.

### Branch-State Check Before Push/Tag

- [ ] Run `git status --short --branch`.
- [ ] Run `git log --oneline --decorate --graph --max-count=8`.
- [ ] Run `git branch -vv`.
- [ ] Confirm the intended commits are reachable from `dev`.
- [ ] Confirm whether `dev` is ahead of `origin/dev` before pushing or tagging.

### v2.0.5 Packaging

- [ ] Run `.\scripts\Build-MIRPackage.ps1`.
- [ ] Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- [ ] Run `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"`.
- [ ] Run `git diff --check`.
- [ ] Copy the zip to a normal Factorio mods folder and confirm Factorio sees it.
- [ ] Record validation results in `docs/test-results.md`.
- [ ] Commit docs, code, changelog, and package together for the tested candidate.

## v2.1.0 Larger Feature Wave

`v2.1.0` should take the harder work after `v2.0.5` feedback. It can also absorb any `v2.0.5` feature that fails proof.

### v2.1.0 Ship Candidates

- [ ] Settings presets: Vanilla-respectful, Megabase-balanced, Unlimited sandbox.
- [ ] Existing agricultural plant rescale if bounded and deduplicated.
- [ ] Scripted-tech diagnostics improvements after `v2.0.5` feedback.
- [ ] High-throughput pump / Der Pump if prototype proof is clean.
- [ ] Pipeline extent startup setting if compatibility proof is clean.
- [ ] Thruster fuel productivity if recipe-productivity proof is clean.
- [ ] Thruster oxidizer productivity if recipe-productivity proof is clean.
- [ ] Oil/fluid recipe productivity if in-game proof is clean.
- [ ] Duplicate native modifier detection for cargo/logistics overlap.
- [ ] Maraxis-like duplicate cargo landing pad fixture or manual test.
- [ ] Krastorio 2 Spaced Out test if compatible with the active Factorio line.
- [ ] Better Robots Extended smoke test.
- [ ] Compatibility docs and manual runtime test results.

### v2.1.0 Acceptance Criteria

- [ ] Every shipped feature has a clear implementation type: native modifier, recipe productivity, scripted event, prototype unlock, or startup setting.
- [ ] No shipped feature uses broad `on_tick` scanning.
- [ ] Any deferred `v2.0.5` scripted feature has its blocker closed or remains disabled/deferred.
- [ ] Every scripted feature documents storage keys, recomputation events, disable behavior, reversal behavior, and multi-force behavior.
- [ ] Any new recipe-productivity stream proves exact recipe IDs and no vanilla/other-mod infinite duplicate.
- [ ] Every startup prototype setting documents when it is applied and why it cannot be runtime research.
- [ ] Compatibility tests include no Space Age, Space Age, Space Age without Quality where supported, custom science/lab fixtures, and at least one large overhaul if available.
- [ ] README, roadmap, compatibility docs, test results, and changelog are updated before release.

## v2.1.5 Quick Feedback Patch

Use `v2.1.5` for small fixes after `v2.1.0`.

- [ ] Fix bugs reported against `v2.1.0`.
- [ ] Add small compatibility profiles only when the missing recipes/prototypes are concrete.
- [ ] Add proven recipe IDs to existing streams when no new architecture is needed.
- [ ] Add locale/docs/validation updates.
- [ ] Rebalance costs or defaults for features already shipped in `v2.1.0`.
- [ ] Backport the tested snapshot as `v1.9.5` after validation.

## v2.2.0 Larger Feature Wave

Use `v2.2.0` for the next larger batch after the `v2.1.x` feedback cycle.

- [ ] Revisit pump/fluid/logistics work that was too large for `v2.1.0`.
- [ ] Revisit advanced settings UX if presets are not enough.
- [ ] Revisit bounded scripted research ideas after the framework has proven stable.
- [ ] Decide which growing ideas should split to companion mods.

## Legacy Backports

Do not reconstruct old releases commit-by-commit for `legacy`. A legacy release is a compatibility port of a tested current-line snapshot.

### v1.9.0 Backport After v2.1.0

- [ ] Finish and validate `v2.1.0` on the Factorio `2.1` line.
- [ ] Tag or branch the exact `v2.1.0` source point, or record the exact release commit hash.
- [ ] Run `git fetch origin`.
- [ ] Run `git checkout -b backport/legacy-1.9.0 origin/legacy`.
- [ ] Run `git merge --no-ff --no-commit v2.1.0`, or `git merge --no-ff --no-commit <v2.1.0-release-commit>` if using a commit hash.
- [ ] Do not cherry-pick a guessed subset unless the full snapshot merge fails and the fallback is documented.
- [ ] Prefer current-line source for shared generator, diagnostics, science-pack handling, recipe matching, compatibility cleanup, validation scripts, docs structure, and localization.

### v1.9.5 Backport After v2.1.5

- [ ] Finish and validate `v2.1.5`.
- [ ] Snapshot or merge the tested `v2.1.5` source point into a temporary legacy backport branch.
- [ ] Apply the same Factorio `2.0` compatibility patch rules as `v1.9.0`.
- [ ] Build `dist/more-infinite-research_1.9.5.zip`.
- [ ] Validate with a Factorio `2.0.x` binary.

### v1.9.9 Final Factorio 2.0 Backport

- [ ] At the Factorio `2.1` stable cutoff target around the end of March, identify the latest tested MIR `2.x.x` release.
- [ ] Backport that latest tested source snapshot to `legacy`.
- [ ] Set the legacy mod version to `1.9.9`.
- [ ] Treat `1.9.9` as the final planned Factorio `2.0` release.
- [ ] Verify the actual Factorio `2.1` stable status before making final-support claims.

### Legacy Compatibility Patch

- [ ] Set `info.json` version to the target `1.9.x` version.
- [ ] Set `info.json` `factorio_version` to `2.0`.
- [ ] Set `info.json` dependencies to the legacy target: `base >= 2.0` and `? space-age`.
- [ ] Remove `base >= 2.1.x` from legacy.
- [ ] Remove `? elevated-rails >= 2.1.x`, `? recycler >= 2.1.x`, `(?) quality >= 2.1.x`, and `? space-age >= 2.1.x` from legacy unless a specific Factorio `2.0` ordering need is proven.
- [ ] Remove or guard `research_cargo_bay_unloading_distance`.
- [ ] Remove or guard `research_cargo_landing_pad_count`.
- [ ] Confirm static validation fails if legacy direct-effect stream definitions still contain `max-cargo-bay-unloading-distance` or `cargo-landing-pad-count`.
- [ ] Verify whether agricultural tower events and `tick_grown` are available in the target Factorio `2.0.x` build before keeping scripted agriculture.
- [ ] Verify whether any pump or pipeline prototype fields exist in Factorio `2.0.x` before keeping them.
- [ ] Rewrite `changelog.txt` as a legacy backport entry, not a copied current-line entry.
- [ ] Update README and compatibility docs to state what is excluded from legacy.

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

These are intentionally not `v2.0.5` or `v2.1.0` MIR core work.

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
