# M.I.R. TODO

Updated: 2026-07-02

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
- [x] Keep scripted spoilage and agriculture streams disabled by default for `v2.0.5`; use manual proof to decide future graduation, presets, or stronger release claims.
- [x] Add runtime scripted-effect debug setting.
- [x] Fix Electric Shooting Speed to include `tesla` ammo category.
- [x] Keep `electric` ammo category coverage for discharge defense.
- [x] Anchor Electric Shooting Speed to discharge defense for vanilla/no-Space-Age icon and prerequisite safety.
- [x] Prefer the Space Age electric-weapons-damage texture for Electric Shooting Speed when that technology exists.
- [x] Add missing shooting-speed descriptions for flamethrower, electric, and Tesla modifiers.
- [x] Add hidden optional Quality load ordering for module productivity.
- [x] Add Omega Drill style mining drill productivity matching.
- [x] Preserve finite vanilla rocket and cannon-shell weapon shooting speed bonuses when MIR overlap handling is enabled.
- [x] Detect and skip recipe productivity already owned by another infinite recipe-productivity technology.
- [x] Confirm Space Age vanilla owns processing unit, low density structure, plastic, and rocket fuel infinite productivity chains.
- [x] Add broad generation-integrity fixture coverage for base-only and Space Age runs.
- [x] Confirm generated `recipe-prod-*` technologies are infinite upgrade chains with effects and count formulas.
- [x] Confirm every enabled vanilla numbered base extension has exactly one serial infinite continuation in base-only and Space Age runs.
- [x] Confirm disabled vanilla numbered base extensions stay absent until force-enabled by validation.
- [x] Confirm every recipe has at most one infinite recipe-productivity owner.
- [x] Confirm circuit productivity ownership by recipe ID, not by similar-looking technology icons.
- [x] Rebuild `dist/more-infinite-research_2.0.5.zip`.
- [x] Run static/package/runtime fixture validation on Factorio 2.1.8.
- [x] Add branch-aware legacy validation guardrails.
- [x] Add static no-`on_tick` validation guard.
- [x] Add static default-off validation for scripted `v2.0.5` candidates.
- [x] Add runtime fixture checks for force-enabled scripted candidate generation and base-only skip behavior.
- [x] Add diagnostic-only native modifier overlap reporting for direct-effect streams.
- [x] Add a Maraxis-like duplicate cargo fixture proving cargo overlaps are reported without changing MIR generation.
- [x] Fix runtime validation temp-copy behavior so fixture scenarios copy package source instead of the whole Git repository.
- [x] Add `docs/pre-manual-2.0.5-report.md`.
- [x] Fix scripted `NothingModifier` effect icons so spoilage/agriculture effect rows do not inherit floating technology constant overlays.
- [x] Merge character logistic trash slots into character inventory slot research and remove the separate current generated trash-slot stream.
- [x] Add a JSON migration from the old generated trash-slot technology ID into the combined inventory/trash technology ID.
- [x] Add runtime validation for the merged inventory/trash effects and absence of the old stream diagnostics.
- [x] Isolate runtime validation with its own Factorio config, write-data directory, and log path.
- [x] Make Character reach bonus use the character mining speed pickaxe icon.
- [x] Complete a v2.0.5 settings confidence pass without adding real preset behavior.
- [x] Make technology tunable settings sort by player-facing name, with default-disabled technology groups surfaced before the enabled alphabetical list.
- [x] Keep diagnostics settings with the one-off startup controls before the technology tunables.
- [x] Add startup-setting warning notes for default-off experimental/sandbox candidates.
- [x] Add dropdown option descriptions for string startup settings.
- [x] Add README settings setup guidance and document exactly what `0` means.
- [x] Add static validation for settings confidence coverage.
- [x] Rename Heavy ammunition productivity to Cannon shell productivity.
- [x] Make Cannon shell productivity use cannon shell item art while keeping cannon shell, artillery shell, railgun ammo, and modded shell/ammo recipe coverage.
- [x] Keep artillery turrets, artillery wagons, railgun turrets, and other buildings out of Cannon shell productivity for `v2.0.5`; revisit as a separate systems/productivity feature if needed.
- [x] Strip inherited vanilla constant badges from generated MIR stream icons before applying MIR's own effect badge.
- [x] Add runtime fixture checks that generated MIR stream icons use the expected effect badge.
- [x] Make Agricultural Growth Speed borrow the vanilla Space Age `agriculture` technology art instead of the agricultural science pack item icon.
- [x] Add runtime fixture coverage for Agricultural Growth Speed's vanilla agriculture technology art.
- [x] Make Processing Unit productivity borrow the processing unit unlock technology art, with the old advanced-electronics ID as an icon fallback.
- [x] Make Wall productivity borrow the Gate technology art.
- [x] Make Rocket Fuel productivity borrow the rocket fuel unlock technology art.
- [x] Make Science pack productivity fall back to base-game Space science pack technology art instead of the automation science pack item icon.
- [x] Add base-game Research productivity with the native `laboratory-productivity` modifier and Military science pack technology art, while skipping it in Space Age where vanilla `research-productivity` exists.
- [x] Add runtime fixture coverage for the new icon sources and base/Space Age Research productivity behavior.
- [x] Run final automated `v2.0.5` release-candidate validation and record it in `docs/test-results.md`.
- [x] Add mod-portal-ready public copy with a complete generated technology catalog.
- [x] Add simplified player-facing `v2.0.5` release notes derived from `changelog.txt`.
- [x] Add simplified player-facing `v1.9.0` legacy release notes derived from `changelog.txt`.
- [x] Release `v1.9.0` from the `legacy` branch as the Factorio `2.0` compatibility port of the tested `v2.0.5` snapshot.

Important release note: the scripted runtime work above is a **default-off v2.0.5 ship candidate**, not automatically deferred to `v2.1.0`. Ship the opt-in implementation with conservative wording after the minimum smoke checks pass. Defer default enablement, presets, or stronger behavior claims until manual proof exists.

## v2.0.5 Quick Feedback Patch

`v2.0.5` should ship the easy and quick changes that are already implemented or simple to validate.

### v2.0.5 Ship Candidates

- [x] Electric Shooting Speed covers `tesla`.
- [x] Electric Shooting Speed still covers `electric`.
- [x] Electric Shooting Speed uses the vanilla discharge defense icon/prerequisite anchor when Space Age is absent.
- [x] Electric Shooting Speed uses the Space Age electric-weapons-damage texture when Space Age is active.
- [x] Flamethrower and electric/Tesla shooting speed modifier descriptions are localized.
- [x] Quality is a hidden optional load-order dependency so module productivity can see quality module recipes.
- [x] Mining drill productivity covers Omega Drill style `omega-drill` and `omega-tau` recipes through validation fixtures.
- [x] Mining drill productivity covers broader visible modded `*-mining-drill` / `*-drill` outputs in the high-tier bucket.
- [x] Weapon shooting speed overlap handling preserves finite vanilla tank cannon speed bonuses.
- [x] Vanilla Space Age `processing-unit-productivity` remains authoritative.
- [x] Vanilla Space Age `low-density-structure-productivity` remains authoritative.
- [x] Vanilla Space Age `plastic-bar-productivity` remains authoritative.
- [x] Vanilla Space Age `rocket-fuel-productivity` remains authoritative.
- [x] Recipe productivity skips effects already owned by another infinite recipe-productivity technology.
- [x] Base-only green, red, and blue circuit productivity owners are validated by recipe ID.
- [x] Space Age green and red circuit productivity stay MIR-owned while processing-unit productivity stays vanilla-owned.
- [x] Runtime fixtures validate all default-enabled vanilla numbered extension chains in base-only and Space Age.
- [x] Runtime fixtures force-enable and validate the normally disabled inserter-capacity continuation in base-only and Space Age.
- [x] Scripted `nothing` effect icons use compact effect-row icon stacks without floating technology constant overlays.
- [x] Character inventory slot research also grants character logistic trash slots.
- [x] Standalone character logistic trash slot research is removed from current generation.
- [x] Existing old trash-slot technology progress has a JSON migration into the combined inventory/trash technology.
- [x] Package includes `control.lua` and `control/`.
- [x] Package includes `migrations/`.
- [x] Package includes and mirrors the current `docs/` tree without requiring release docs to stay at fixed root paths.
- [x] Startup setting labels, descriptions, ordering, dropdown help, and experimental warnings are refreshed without changing generated technology names or defaults.
- [x] README documents recommended default, vanilla-respectful, megabase, modpack compatibility, and debug/reporting settings patterns.
- [x] Cannon shell productivity naming and icon art are aligned with the Cannon Shooting Speed cannon-shell icon family.
- [x] Runtime fixtures assert generated MIR icon badges match effect types, including Electric Shooting Speed using speed instead of inherited damage.
- [x] Scripted spoilage/agriculture runtime effects honor settings presets, `Force enabled`, `Force disabled`, and `Custom/manual` legacy enable checkboxes.
- [ ] Spoilage preservation passes the manual blockers below.
- [ ] Agricultural growth speed for newly planted tower crops passes the manual blockers below.
- [ ] README/changelog state the exact measured behavior, especially for existing spoilable stacks and existing plants.

### v2.0.5 Acceptance Criteria

- [x] Static validation passes.
- [x] Package validation passes.
- [x] Runtime fixture validation passes on the supported Factorio `2.1.x` binary.
- [x] The current `docs/` tree is included in the package.
- [x] Package validation follows the current documentation layout instead of hard-coding release doc paths.
- [x] README, docs, changelog, and package agree on release scope.
- [ ] Runtime feature claims are backed by manual/runtime validation.
- [x] `dist/more-infinite-research_2.0.5.zip` is rebuilt from current source.
- [x] Changelog has an entry matching `info.json` version.
- [x] Zip filename and internal `info.json` version match `info.json`.
- [x] Zip excludes dev-only files and includes required docs/source/locale/control/migration files.
- [x] Git tree is clean after build.
- [x] Static validation requires setting note keys, dropdown option descriptions, diagnostics order, and default-off scripted setting coverage.

### v2.0.5 API And ID Verification

- [x] Confirm Tesla gun, Tesla ammo, and Tesla turret use `ammo_category = "tesla"` in installed Space Age prototypes.
- [x] Confirm discharge defense uses `ammo_category = "electric"` in base prototypes.
- [x] Confirm Space Age `electric-weapons-damage-1` provides the intended electric weapon technology texture.
- [x] Confirm `gun-speed` modifier is keyed by ammo category.
- [x] Confirm current base/Space Age locale files do not provide all generated shooting-speed modifier descriptions MIR needs.
- [x] Confirm Factorio supports hidden optional dependencies through the `(?)` dependency prefix.
- [x] Confirm Factorio supports JSON migrations for technology prototype ID consolidation.
- [x] Confirm vanilla Space Age `processing-unit-productivity` owns `processing-unit`.
- [x] Confirm vanilla Space Age `low-density-structure-productivity` owns `low-density-structure` and `casting-low-density-structure`.
- [x] Confirm vanilla Space Age `plastic-bar-productivity` owns `plastic-bar` and `bioplastic`.
- [x] Confirm vanilla Space Age `rocket-fuel-productivity` owns `rocket-fuel`, `rocket-fuel-from-jelly`, and `ammonia-rocket-fuel`.
- [ ] Re-check official API docs before release if Factorio updates past the local validation version.

### v2.0.5 Scripted-Tech Framework

- [x] Review `storage` layout for long-term stability and document every key in `docs/architecture.md`.
- [ ] Confirm spoilage baseline capture cannot compound MIR's own multiplier across load/configuration cycles.
- [x] Decide whether research reversal should restore baseline immediately when no forces have levels.
- [ ] Confirm behavior when another mod also writes `game.difficulty_settings.spoil_time_modifier`.
- [x] Store only MIR's own applied spoilage multiplier and remove/divide it out before recalculating when possible.
- [x] Handle `on_init`.
- [x] Handle `on_configuration_changed`.
- [x] Handle `on_research_finished`.
- [x] Handle `on_research_reversed`.
- [x] Handle `on_technology_effects_reset`.
- [x] Confirm static validation fails on accidental `on_tick` or `script.on_nth_tick`.

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

- [x] Run `git status --short --branch`.
- [x] Run `git log --oneline --decorate --graph --max-count=8`.
- [x] Run `git branch -vv`.
- [x] Confirm the intended commits are reachable from `dev`.
- [x] Confirm whether `dev` is ahead of `origin/dev` before pushing or tagging.

### v2.0.5 Packaging

- [x] Run `.\scripts\Build-MIRPackage.ps1`.
- [x] Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`.
- [x] Run `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"`.
- [x] Run `.\scripts\Test-MIRBranchPolicy.ps1`.
- [x] Run `git diff --check`.
- [ ] Copy the zip to a normal Factorio mods folder and confirm Factorio sees it.
- [x] Record validation results in `docs/test-results.md`.
- [x] Commit docs, code, changelog, and package together for the tested candidate.

## v1.9.0 Legacy Backport After v2.0.5

Status: released from the `legacy` branch. Keep this section as historical process evidence for the first legacy backport.

- [x] Finish and validate `v2.0.5` on the Factorio `2.1` line.
- [x] Tag or branch the exact `v2.0.5` source point, or record the exact release commit hash.
- [x] Run `git fetch origin`.
- [x] Merge the tested `v2.0.5` snapshot into `legacy`.
- [x] Do not cherry-pick a guessed subset unless the full snapshot merge fails and the fallback is documented.
- [x] Prefer current-line source for shared generator, diagnostics, science-pack handling, recipe matching, compatibility cleanup, validation scripts, docs structure, and localization.
- [x] Apply the legacy compatibility patch below before building or publishing.
- [x] Validate with a real Factorio `2.0.x` binary, not the Steam-updated Factorio `2.1.x` binary.

## v2.1.0 Larger Feature Wave

`v2.1.0` should take the harder work after `v2.0.5` feedback, but it should stay selective. Use `docs/release-plan-2.1.0.md` as the release-gated implementation plan.

Theme:

```text
user-facing control + compatibility discipline + proof-gated expansion
```

Do not turn `v2.1.0` into a bucket for every plausible feature idea.

### v2.1.0 Milestone / Issue Setup

- [ ] Create a GitHub `v2.1.0` milestone.
- [ ] Create issue: `v2.1.0: settings presets and override model`.
- [ ] Create issue: `v2.1.0: native modifier overlap policy`.
- [ ] Create issue: `v2.1.0: icon source resolver and asset policy`.
- [ ] Create issue: `v2.1.0: spoilage preservation manual validation`.
- [ ] Create issue: `v2.1.0: agricultural growth manual validation`.
- [ ] Create issue: `v2.1.0: existing agricultural plant rescale spike`.
- [ ] Create issue: `v2.1.0: high-throughput pump prototype unlock`.
- [ ] Create issue: `v2.1.0: pipeline extent startup setting spike`.
- [ ] Create issue: `v2.1.0: thruster fuel and oxidizer productivity spike`.
- [ ] Create issue: `v2.1.0: oil/fluid recipe productivity spike`.
- [ ] Create issue: `v2.1.0: compatibility matrix`.
- [ ] Create issue: `v2.1.0: release packaging and docs`.
- [ ] Each issue includes goal, scope, out-of-scope, acceptance criteria, validation, and release-note wording.

### v2.1.0 Ship Candidates

- [x] Settings presets: `Custom/manual`, `Vanilla-respectful`, `Megabase-balanced`, `Unlimited sandbox` implemented for technology enablement.
- [x] Preset override model: per-technology `Use settings mode`, `Force enabled`, and `Force disabled` policy prevents preset modes from silently contradicting explicit enablement choices.
- [ ] Native modifier overlap policy: prefer existing owner, warn only, prefer MIR, or allow duplicates.
- [x] Icon source resolver: prefer loaded Space Age technology art when available, optionally reference installed-but-disabled Space Age icon files behind `mir-use-installed-space-age-icons`, keep default base-only fallbacks safe, and do not redistribute original Space Age asset files inside MIR.
- [ ] Scripted spoilage hardening: manual results for existing/new stacks, reversal, disable, baseline, and multi-force behavior.
- [ ] Scripted agriculture hardening: newly planted crops verified; existing-plant rescale only if bounded and deduplicated.
- [ ] Existing agricultural plant rescale if bounded, tower-scoped, deduplicated, reversible, and large-farm tested.
- [ ] Scripted-tech diagnostics improvements after `v2.0.5` feedback.
- [ ] High-throughput pump prototype unlock if the scope remains one optional pump entity with no runtime fluid scripting.
- [ ] Pipeline extent startup setting only if compatibility proof is clean; otherwise keep as spike.
- [ ] Thruster fuel productivity only if recipe-productivity proof is clean.
- [ ] Thruster oxidizer productivity only if recipe-productivity proof is clean.
- [ ] Oil/fluid recipe productivity only if in-game proof is clean for fluid-only and mixed-output recipes.
- [ ] Real Maraxis-like duplicate cargo landing pad manual test when a compatible target is available.
- [ ] Krastorio 2 Spaced Out test if compatible with the active Factorio line.
- [ ] Better Robots Extended smoke test.
- [ ] Compatibility docs and manual runtime test results.

### v2.1.0 Spike / Defer Decisions

- [ ] Pipeline extent multiplier is classified as startup-setting spike unless tests prove safe.
- [ ] Thruster fuel/oxidizer productivity is classified as recipe-productivity spike unless exact recipes prove clean.
- [ ] Oil/fluid productivity is classified as recipe-productivity spike unless exact recipes prove clean.
- [ ] Agricultural yield / fruit yield is spike-only unless a clean bounded path exists.
- [ ] Quality module enrichment is spike/defer or add-on; do not implement runtime module mutation in core MIR.
- [ ] Roboport range is spike/defer unless a clean native modifier or small prototype-tier path exists.
- [ ] True thruster thrust research remains rejected/deferred unless Factorio exposes a native modifier.
- [ ] Runtime platform speed mutation remains rejected.
- [ ] Runtime quality odds mutation remains rejected.
- [ ] Refrigeration, greenhouses, super-bacteria, and broad fluid systems remain companion/defer scope.

### v2.1.0 Acceptance Criteria

- [ ] Every shipped feature has a clear implementation type: native modifier, recipe productivity, scripted event, prototype unlock, or startup setting.
- [ ] No shipped feature uses broad `on_tick` scanning.
- [ ] Any deferred `v2.0.5` scripted feature has its blocker closed or remains disabled/deferred.
- [ ] Every scripted feature documents storage keys, recomputation events, disable behavior, reversal behavior, and multi-force behavior.
- [ ] Any new recipe-productivity stream proves exact recipe IDs and no vanilla/other-mod infinite duplicate.
- [ ] Every startup prototype setting documents when it is applied and why it cannot be runtime research.
- [ ] Compatibility tests include no Space Age, Space Age, Space Age without Quality where supported, custom science/lab fixtures, and at least one large overhaul if available.
- [x] Presets have validation for expected generated stream and base-extension decisions.
- [ ] Native modifier overlap policy has validation for duplicate cargo/native modifier scenarios.
- [x] Icon resolver validation proves default base-only runs do not resolve generated icons to `__space-age__` paths, opt-in base-only runs can use installed Space Age icon paths, and Space Age runs still prefer intended Space Age art.
- [x] Package validation fails copied Space Age asset files unless an explicit source/license allowlist entry exists.
- [ ] Conditional spikes are either promoted with proof or explicitly moved out of `v2.1.0`.
- [ ] `info.json` version is bumped to `2.1.0`.
- [ ] `changelog.txt` has a dated `2.1.0` entry.
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

### v1.9.5 Backport After v2.1.5

- [ ] Finish and validate `v2.1.5`.
- [ ] Snapshot or merge the tested `v2.1.5` source point into a temporary legacy backport branch.
- [ ] Apply the same Factorio `2.0` compatibility patch rules as `v1.9.0`.
- [ ] Build `dist/more-infinite-research_1.9.5.zip`.
- [ ] Validate with a Factorio `2.0.x` binary.

### v1.9.9 Final Factorio 2.0 Backport

- [ ] When Factorio `2.1` becomes stable or another verified upstream cutoff is chosen, identify the latest tested MIR `2.x.x` release.
- [ ] Backport that latest tested source snapshot to `legacy`.
- [ ] Set the legacy mod version to `1.9.9`.
- [ ] Treat `1.9.9` as the final planned Factorio `2.0` release.
- [ ] Verify the actual Factorio `2.1` stable status before making final-support claims.

### Legacy Compatibility Patch

- [x] Set `info.json` version to the target `1.9.x` version.
- [x] Set `info.json` `factorio_version` to `2.0`.
- [x] Set `info.json` dependencies to the legacy target: `base >= 2.0`, hidden optional `quality`, and `? space-age`.
- [x] Remove `base >= 2.1.x` from legacy.
- [x] Remove `? elevated-rails >= 2.1.x`, `? recycler >= 2.1.x`, `(?) quality >= 2.1.x`, and `? space-age >= 2.1.x` from legacy unless a specific Factorio `2.0` ordering need is proven.
- [x] Remove or guard `research_cargo_bay_unloading_distance`.
- [x] Remove or guard `research_cargo_landing_pad_count`.
- [x] Confirm static validation fails if legacy direct-effect stream definitions still contain `max-cargo-bay-unloading-distance` or `cargo-landing-pad-count`.
- [x] Treat scripted agriculture as non-blocking for `1.9.0`: the stream remains disabled by default and no measured behavior claim is made.
- [x] Treat pump and pipeline prototype fields as not applicable for `1.9.0`: no pump or pipeline feature ships in this release.
- [x] Rewrite `changelog.txt` as a legacy backport entry, not a copied current-line entry.
- [x] Update README and compatibility docs to state what is excluded from legacy.

### Legacy Validation

- [x] Make `scripts/Invoke-MIRValidation.ps1` branch-aware from `info.json`.
- [x] Static validation checks `factorio_version = "2.0"` on legacy.
- [x] Static validation checks `base >= 2.0` style metadata on legacy.
- [x] Static validation checks 2.1-only cargo modifiers are absent on legacy.
- [x] Static validation skips 2.1-only cargo runtime fixture expectations on legacy.
- [x] Run `.\scripts\Build-MIRPackage.ps1` on legacy.
- [x] Run `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly` on legacy.
- [x] Run `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Path\To\Factorio-2.0.x\bin\x64\factorio.exe"` on legacy.
- [x] Do not validate the legacy port with the Steam-updated Factorio `2.1.x` binary.
- [x] Fix initial Factorio `2.0.77` failures in this order: fixture metadata, unresearchable science-pack fixture shape, docs/package evidence.
- [x] Keep the legacy diff small: metadata, docs, validation branching, package name, fixture metadata, and explicit removal of Factorio `2.1`-only surfaces.
- [x] Load the rebuilt `1.9.0` release zip from isolated normal mod directories in base-only and Space Age modes.
- [x] Create a base-only `1.2.9` save and benchmark-load it under `1.9.0` as a basic old-save compatibility smoke.
- [ ] If available, manually load a real legacy save with progress in the old standalone trash-slot technology and confirm the JSON migration moves progress into the combined inventory/trash technology.

## Companion Mod Backlog

These are intentionally not `v2.0.5` or `v2.1.0` MIR core work.

- [ ] Cold Chain / CryoPants: freezer chest, freeze/thaw recipes, refrigerated transport, freshness penalty.
- [ ] Advanced Agriculture: greenhouse, off-world fruit, heating constraints, artificial soil loops.
- [ ] Advanced Quality Research: higher quality module tiers, quality odds tuning, quality-based spoilage.
- [ ] Quality module enrichment research: prototype/module-tier spike only; do not implement as runtime module mutation in core MIR.
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

- [x] `git status --short --branch`
- [x] `rg "data.raw.tool|tool_exists|has_tool|PACKS_ALL" prototypes`
- [x] `rg "on_tick" control prototypes`
- [x] `rg "icon_mipmaps" prototypes`
- [x] `.\scripts\Build-MIRPackage.ps1`
- [x] `.\scripts\Invoke-MIRValidation.ps1 -StaticOnly`
- [x] `.\scripts\Invoke-MIRValidation.ps1 -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"`
- [x] `.\scripts\Test-MIRBranchPolicy.ps1`
- [x] `git diff --check`
- [ ] Load the release zip from a normal Factorio mods folder.
- [x] Record validation results in `docs/test-results.md`.
- [x] Commit docs, code, changelog, and package together for the tested candidate.
