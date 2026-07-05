# M.I.R. TODO

Updated: 2026-07-06

This is the executable task list for the next More Infinite Research releases. Keep durable future work here, not only in derivative planning docs, so the project still has its task and release plan if the `docs/` tree is reorganized or partially lost.

Use `docs/roadmap.md` for release scope, product boundaries, rationale, and high-level "why" explanations. Use `docs/notes/post-2.0-feature-plan.md` for the deeper idea archive, and `docs/notes/legacy-backport-cadence.md` for the expanded older-line backport ladder. Use `changelog.txt` as the authoritative past-change ledger.

## Working Rules

- Target `dev` for active Factorio `2.1` development.
- Treat `.5` releases as quick feedback patches for small, bounded, tested changes.
- Treat `.0` releases as larger feature waves.
- Aim for one validated Factorio `2.1` current-line update per week from 2026-07-06 through December 2026.
- Aim for one older-line compatibility backport per day during the week-before through week-after Factorio `2.1` release celebration window.
- Backport tested current-line snapshots to `legacy` as Factorio `2.0` compatible `1.9.x` releases, and treat older Factorio line ports as separate validation-gated target-line branches.
- Do not rebuild `legacy` commit-by-commit from older releases.
- Keep generated technology names stable unless a tested migration exists.
- Prefer native modifiers and recipe productivity.
- Scripted effects must be event-driven, bounded, reversible where practical, and documented.
- Do not add broad `on_tick` scans for inventories, belts, containers, item stacks, surfaces, or all entities.
- Never add `character-item-pickup-distance` or `character-loot-pickup-distance` technology effects; large pickup radii can vacuum belt items into inventories and cause severe lag.
- Commit documentation and implementation changes at the end of each completed work turn.
- Keep future work, deferred work, recurring checklists, and issue-creation tasks in this root `todo.md`.
- Keep past shipped changes in `changelog.txt`; release notes and mod-portal copy are derivative summaries.
- Keep `docs/roadmap.md` synchronized with this file and `changelog.txt`, but at a higher level with rationale, scope boundaries, and links or placeholders for issues.
- Treat the compatibility planner as the future contract between prototype discovery, owner classification, validation, mutation, and diagnostics.
- Do not publish the next compatibility-heavy archive until static validation, runtime Factorio validation, package build, diff check, and audit smoke have all passed after the final refactor.

## Immediate Status

Done in the current development branch:

- [x] Bump mod metadata to `2.0.5`.
- [x] Add `control.lua`.
- [x] Add scripted-tech manager under `control/scripted-techs.lua`.
- [x] Add spoilage preservation scripted effect.
- [x] Add agricultural growth speed scripted effect.
- [x] Add visible `nothing` effects for scripted technologies.
- [x] Add settings/defaults for the two scripted streams.
- [x] Keep scripted spoilage and agriculture streams disabled by default for `v2.0.5`; ship them as conservative opt-in candidates while long-running manual save evidence accumulates.
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
- [x] Add `docs/notes/archive/pre-manual-2.0.5-report.md`.
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
- [x] Implement `v2.1.0` fluid-output recipe productivity streams for oil processing, oil cracking, lubricant, sulfuric acid, acid neutralization, and Space Age thruster propellants.
- [x] Implement fluid-output recipe matching, fluid icon fallback, and required-fluid stream gates.
- [x] Implement the strictly opt-in startup-only pipeline extent multiplier dropdown with default `100%` unchanged behavior and no fluidbox scan when disabled.
- [x] Add runtime fixtures for fluid-output productivity ownership and startup pipeline extent scaling.
- [x] Add a hard safety guard and validation coverage preventing character item-pickup and loot-pickup reach effects from MIR-generated technologies.
- [x] Add conservative vanilla Space Age productivity-family adoption for processing units, plastic, low density structures, and rocket fuel.
- [x] Add existing-save technology-effect reset keyed by the actual adopted productivity-family signature.
- [x] Add known Plates n Circuit Productivity replacement for fully covered competing plate and circuit productivity technologies.

Important release note: the scripted runtime work above is a **default-off v2.0.5 ship candidate**, not automatically deferred to `v2.1.0`. The implementation is complete for the default-off release posture. Defer default enablement, presets, or stronger behavior claims until long-running manual proof exists.

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
- [x] Scripted spoilage/agriculture runtime effects honor the same enable checkboxes used by data-stage technology generation.
- [x] Spoilage preservation is release-complete as a default-off experimental candidate with conservative claims.
- [x] Agricultural growth speed for newly planted tower crops is release-complete as a default-off experimental candidate with conservative claims.
- [x] README/changelog avoid exact measured claims for existing spoilable stacks and existing plants until manual evidence exists.

### v2.0.5 Acceptance Criteria

- [x] Static validation passes.
- [x] Package validation passes.
- [x] Runtime fixture validation passes on the supported Factorio `2.1.x` binary.
- [x] The current `docs/` tree is included in the package.
- [x] Package validation follows the current documentation layout instead of hard-coding release doc paths.
- [x] README, docs, changelog, and package agree on release scope.
- [x] Runtime feature claims stay conservative unless backed by manual/runtime validation.
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

### v2.0.5 Spoilage Preservation Long-Running Manual Evidence

These checks are no longer release blockers while Spoilage preservation remains disabled by default and documented conservatively. Use them to decide later default enablement, preset inclusion, stronger release claims, or bug fixes.

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

### v2.0.5 Agricultural Growth Speed Long-Running Manual Evidence

These checks are no longer release blockers while Agricultural growth speed remains disabled by default and documented conservatively. Use them to decide later default enablement, preset inclusion, stronger release claims, or bug fixes.

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

`v2.1.0` should take the harder work after `v2.0.5` feedback, but it should stay selective. Use `docs/notes/release-plan-2.1.0.md` as the detailed release-gated implementation note, and keep the durable release tasks mirrored here.

Theme:

```text
user-facing control + compatibility discipline + proof-gated expansion
```

Do not turn `v2.1.0` into a bucket for every plausible feature idea.

### v2.1.0 Milestone / Issue Setup

- [ ] Create a GitHub `v2.1.0` milestone.
- [ ] Create issue: `later: shareable settings profile import/export`.
- [ ] Create issue: `v2.1.0: native modifier overlap policy`.
- [ ] Create issue: `v2.1.0: icon source resolver and asset policy`.
- [ ] Create issue: `v2.1.0: spoilage preservation manual validation`.
- [ ] Create issue: `v2.1.0: agricultural growth manual validation`.
- [ ] Create issue: `v2.1.0: existing agricultural plant rescale spike`.
- [ ] Create issue: `v2.1.0: high-throughput pump prototype unlock`.
- [ ] Create issue: `v2.1.0: pipeline extent startup setting`.
- [ ] Create issue: `v2.1.0: thruster fuel and oxidizer productivity`.
- [ ] Create issue: `v2.1.0: oil/fluid recipe productivity`.
- [ ] Create issue: `v2.1.0: compatibility matrix`.
- [ ] Create issue: `v2.1.0: compatibility audit harness follow-up`.
- [ ] Create issue: `v2.1.0: profile-driven owner classification follow-up`.
- [ ] Create issue: `docs: keep root todo, changelog, and roadmap authority synchronized`.
- [ ] Create issue: `v2.1.0: release packaging and docs`.
- [ ] Each issue includes goal, scope, out-of-scope, acceptance criteria, validation, and release-note wording.

### v2.1.0 Ship Candidates

- [x] Settings preset mode and per-technology enable-policy dropdowns removed before release; individual enable checkboxes are the single enablement path.
- [ ] Shareable presets/import-export design for a later release, without adding per-technology override dropdowns.
- [x] Broad native modifier overlap policy explicitly deferred; targeted recipe-productivity compatibility shipped first.
- [x] Icon source resolver: prefer loaded Space Age technology art when available, optionally reference installed-but-disabled Space Age icon files behind `mir-use-installed-space-age-icons`, keep default base-only fallbacks safe, and do not redistribute original Space Age asset files inside MIR.
- [ ] Scripted spoilage hardening: manual results for existing/new stacks, reversal, disable, baseline, and multi-force behavior.
- [ ] Scripted agriculture hardening: newly planted crops verified; existing-plant rescale only if bounded and deduplicated.
- [ ] Existing agricultural plant rescale if bounded, tower-scoped, deduplicated, reversible, and large-farm tested.
- [ ] Scripted-tech diagnostics improvements after `v2.0.5` feedback.
- [ ] High-throughput pump prototype unlock if the scope remains one optional pump entity with no runtime fluid scripting.
- [x] Pipeline extent startup setting with default `100%`/off behavior implemented; ship only if compatibility proof is clean.
- [x] Thruster fuel productivity through native recipe productivity implemented; ship only if exact vanilla and Space Age recipes prove clean.
- [x] Thruster oxidizer productivity through native recipe productivity implemented; ship only if exact vanilla and Space Age recipes prove clean.
- [x] Oil/fluid recipe productivity through native recipe productivity implemented; ship only if fluid-only and mixed-output recipe proof is clean.
- [ ] Real Maraxis-like duplicate cargo landing pad manual test when a compatible target is available.
- [ ] Krastorio 2 Spaced Out test if compatible with the active Factorio line.
- [ ] Better Robots Extended smoke test.
- [x] Compatibility docs and automated runtime test results for shipped `v2.1.0` features.
- [x] Profile-driven recipe-productivity owner classification moved out of the generator.
- [x] Vanilla productivity-family adoption moved into a dedicated compatibility module.
- [x] Parser-friendly generation audit rows added for stream/native-overlap/recipe-owner diagnostics.
- [x] Local mod-portal compatibility audit harness added with committed matrix inputs and ignored generated reports.
- [x] Extended compatibility automation added: executable manual scenarios, sharded/resumable audits, grouped failure reports, review-only profile stubs, tiered extended-test wrapper, and self-hosted workflow.
- [x] Documentation hierarchy reorganized: root `todo.md` is future-work authority, `changelog.txt` is past-change authority, `docs/roadmap.md` is high-level rationale, and `docs/notes/` contains derivative plans/release notes/archive material.
- [ ] Run full mod-portal compatibility audit with credentials and a local Factorio binary.
- [ ] Convert recurring audit failures into small declarative compatibility profiles only when the report shows concrete, repeatable patterns.
- [x] Runtime-test the refactored recipe-productivity owner/adoption modules with `FACTORIO_BIN` configured.

### Compatibility Architecture Next Steps

The current refactor is a strong foundation, but the final compatibility system should make a plan object the central artifact:

```text
discover facts
  -> classify owners
  -> build complete plan
  -> validate plan
  -> mutate prototypes
  -> emit audit rows from the plan
```

- [ ] Make the MIR generation plan an explicit object produced before prototype mutation.
- [ ] Add `prototypes/planning/discovery.lua` or equivalent fact collection around active mods, recipes, technologies, labs, science packs, existing owners, and configured profiles.
- [ ] Add `prototypes/planning/planner.lua` or equivalent planning logic that converts facts, streams, and profiles into recipe-level actions.
- [ ] Add `prototypes/planning/plan-validator.lua` or equivalent validation before any prototype mutation.
- [ ] Add `prototypes/planning/plan-executor.lua` or equivalent mutation layer so generation/adoption/replacement apply only validated plan rows.
- [ ] Add `prototypes/planning/plan-diagnostics.lua` or equivalent diagnostics layer so audit rows are emitted from the final plan rather than scattered generation sites.
- [ ] Fixture-test the plan without relying only on mutated `data.raw` inspection.
- [ ] Compare generated plans across representative modsets to detect compatibility regressions before prototype application.
- [ ] Keep `tech-gen.lua` as orchestration glue once planner/executor modules exist.

### Compatibility Profile Schema

- [ ] Add strict schema validation for compatibility profiles before they affect generation.
- [ ] Reject profiles with missing stream names.
- [ ] Reject profiles that reference unknown streams.
- [ ] Reject broad unanchored technology patterns unless a profile explicitly marks them as reviewed.
- [ ] Reject replacement profiles that do not require full replacement coverage.
- [ ] Reject adoption profiles that do not define uniform-change or copy-owner behavior explicitly.
- [ ] Reject product names that cannot be reconciled with the stream's output policy.
- [ ] Require profile modes to be explicit, such as known-competitor replacement, vanilla-family adoption, suppression-only, or review-required stub.

### Structured Audit Diagnostics

- [ ] Standardize a fixed structured audit prefix, such as `[MIR-AUDIT] schema=1`.
- [ ] Emit stable `facts` rows for active mods, relevant startup settings, stream count, recipe count, and profile count.
- [ ] Emit stable `stream` rows for stream-level generated/skipped/adopted/suppressed decisions.
- [ ] Emit stable `recipe` rows for recipe-level action decisions.
- [ ] Emit stable `owner` rows for exact recipe-productivity owner classification.
- [ ] Emit stable `adoption` rows for recipes appended to existing vanilla productivity-family technologies.
- [ ] Emit stable `replacement` rows for known competitor technologies prepared or removed.
- [ ] Emit stable `suppression` rows for MIR-suppressed recipes owned by unknown or unsafe external technologies.
- [ ] Emit stable `conflict` rows for ambiguous or unsafe states.
- [ ] Emit stable `integrity` rows for duplicate owners, missing prerequisites, invalid science packs, invalid recipes, and package/runtime assertions.
- [ ] Update the PowerShell diagnostics parser to consume structured fields only, avoiding fuzzy prose parsing.

### Compatibility Testing And Audit Expansion

- [x] Configure `FACTORIO_BIN` and rerun full runtime validation after the compatibility refactor, competitor hardening, science-pack rebalance, and Space Age productivity split.
- [x] Add executable manual-scenario automation for curated modpacks and high-risk compatibility surfaces.
- [x] Add sharding and lockfile resume support for long compatibility audits.
- [x] Add grouped audit result conversion for load failures, duplicate owners, known competitors, unknown external owners, invalid science, missing prerequisites, productivity-disallowed recipes, and missing audit rows.
- [x] Add strict `-FailOnAuditFailures` wrapper semantics so unexpected grouped audit failures can fail CI-style gates.
- [x] Add exploratory `-CollectAll` wrapper behavior so overnight runs can keep collecting after individual scenario failures.
- [x] Make `AuditSmoke` deterministic by using the committed `space-age-baseline` manual-scenario metadata path rather than a volatile catalog sample.
- [x] Add per-scenario Factorio load timeouts for unattended compatibility runs.
- [x] Expose `-FromLockfile` on the extended wrapper for reproducible sharded audits.
- [x] Skip unresolved dependency scenarios before Factorio load checks by default, with `-ContinueOnDependencyFailure` for explicit partial-modset diagnostics.
- [x] Add reviewed expected-failure fixture support so grouped reports can distinguish expected and unexpected failures.
- [x] Add local modpack zip support with `LocalModZips`, `-LocalModZipDirs`, local `source_path` lock entries, and recommended-dependency inclusion for pack wrapper mods.
- [x] Add offline local mod-library support with `-LocalModLibraryDirs`, `-Offline`, curated `LocalLibraryScenarios`, and mega-smash/local-combination fixtures for read-only downloaded archive collections.
- [x] Add generated local-library scenarios for all-local mega, metadata clusters, and capped pairwise stress runs.
- [x] Add local-root sharding for `LocalModZips` with `-ShardLocalModZips`, `-StartIndex`, and `-ShardSize`.
- [x] Checkpoint `load-results.json` after every scenario so interrupted overnight runs still leave partial results.
- [x] Emit `missing-dependencies.md/json/csv` from grouped compatibility conversion.
- [x] Add `Start-MIROvernightLocalSweep.ps1` as the safe bedtime entrypoint for the local `2.1` offline sweep.
- [x] Add `Show-MIROvernightSummary.ps1` for next-morning grouped failure, missing dependency, and profile-candidate triage.
- [x] Add `Invoke-MIRReleaseTargetedGate.ps1` as the narrow current-commit release gate for `2.1.0`.
- [x] Fix local overnight sweep audit parsing so blank Factorio log lines cannot abort `GeneratedLocalScenarios` or `LocalModZips`.
- [x] Fix isolated compatibility mod lists so installed official DLC mods are disabled unless requested, and Space Age scenarios enable the complete official bundle.
- [ ] Run the overnight local `2.1` library sweep against `C:\Projects\Factorio\testmods_2.1` using individual roots plus curated local-library scenarios.
- [ ] Fill missing dependency zips reported by the local `2.1` library sweep, then rerun only the affected scenarios.
- [ ] Run a top-25 Mod Portal audit for Factorio `2.1` with real downloads, credentials, and a local Factorio binary.
- [ ] Run a full `downloads_count >= 10000` Mod Portal audit for Factorio `2.0` and `2.1`.
- [ ] Run the grouped audit converter on real top-25 and full-audit outputs and triage the resulting failure buckets.
- [ ] Populate `fixtures/compat-matrix/expected-failures.json` only after a real audit finding has been reviewed and accepted as non-MIR external breakage.
- [ ] Convert recurring verified failures into declarative compatibility profiles only after grouped audit evidence exists.
- [ ] Add existing-save validation for profile-driven adoption and replacement, including signature-change refresh behavior.

### Profile Stub Tooling

- [x] Add `scripts/New-MIRCompatProfileStub.ps1`.
- [x] Let the stub generator read `compat-failures.grouped.json` and a grouped failure ID.
- [x] Generate review-required Lua profile stubs with audit-run evidence, candidate tech patterns, affected streams, duplicate recipes, and external owners where the grouped evidence contains them.
- [x] Keep generated stubs disabled or review-required until manually refined.
- [x] Never let profile-stub generation automatically enable a compatibility profile.
- [ ] Refine stub generation after the explicit planner emits richer replacement/adoption/suppression evidence.

### Extended Test Tooling

The current overnight/local-library automation is usable. Keep `scripts/mir.ps1` as the preferred human front door, use JSON run profiles for defaults, and treat `scripts/MIRCli/` as a small private helper folder. Do not expand it into a framework unless repeated script-level pain proves the need.

- [x] Add a shared `scripts/MIRCli/` PowerShell module layer for console formatting, run context, event logging, process supervision, checkpoints, artifact indexing, report helpers, path resolution, local mod indexing, and power-management helpers.
- [x] Add timestamped status output with stable textual tokens such as `[RUN]`, `[STEP]`, `[SCEN]`, `[PASS]`, `[SKIP]`, `[TIME]`, and `[FAIL]`, with optional color controlled by `-ColorMode`, `-NoColor`, `-Quiet`, and `-CI`.
- [x] Add `events.jsonl` helper support as a structured append-only event log for run start, tier start/result, scenario start/result, process start/result, timeout, dependency skip, and summary events.
- [x] Add `run-manifest.json` helper support so each long run can record run ID, repo root, git branch/commit, Factorio binary/version, MIR version, selected tiers, offline/local library inputs, timeout, and pairwise settings.
- [x] Wire `run-manifest.json` and `events.jsonl` into `Invoke-MIRExtendedTests.ps1` and `Start-MIROvernightLocalSweep.ps1`.
- [ ] Add canonical scenario statuses such as `pending`, `running`, `passed`, `failed`, `timed_out`, `skipped_dependency`, `skipped_incompatible`, `expected_failure`, `unexpected_failure`, and `cancelled` while preserving existing booleans for compatibility.
- [ ] Add `scenario-state.json` and first-class resume controls: `-Resume`, `-RerunFailed`, `-RerunTimedOut`, `-RerunSkipped`, `-RerunUnexpected`, and `-RerunScenarioNames`.
- [ ] Extract Factorio process handling into a reusable process supervisor with timeout, process-tree cleanup, elapsed time, exit-code classification, failure-tail capture, and optional retry policy.
- [ ] Add retry controls for transient cases only: `-MaxRetries`, `-RetryOnTimeout`, `-RetryOnExitCodes`, and `-RetryDelaySeconds`.
- [x] Add `artifact-index.json` helper support so summary tooling can find manifests, transcripts, events, grouped failures, missing dependencies, profile candidates, and reports without path guessing.
- [x] Add initial static `index.html` report generation support for run artifact folders.
- [x] Wire `artifact-index.json` and `index.html` into extended-test and overnight-local output roots.
- [ ] Add missing-dependency shopping-list artifacts such as `missing-dependencies.todo.md` and `missing-dependencies.download-plan.json`.
- [x] Add initial cached local mod library index generation with zip SHA1, size/mtime, Factorio version, and dependencies.
- [ ] Add optional `-LinkMode Copy|Hardlink|Symlink` for large local libraries, with safe fallback to copy when hardlinks/symlinks are unavailable.
- [ ] Add conservative `-Parallelism` support for metadata/report work first, keeping Factorio load checks sequential by default.
- [x] Add a stable `scripts/mir.ps1` facade and initial JSON run profiles.
- [x] Move the default local audit command behind `fixtures/run-profiles/local-audit-2.1.json` instead of hardcoding it in `mir.ps1`.
- [x] Add `scripts/Test-MIRPowerShellQuality.ps1` for parsing every script, artifact-ignore checks, duplicate parameter detection, and optional PSScriptAnalyzer when installed.
- [x] Add `FactorioLine` support to the existing release gate, extended runner, compatibility audit, overnight sweep, and `mir.ps1` profile dispatch.
- [x] Add Factorio `2.0` run profiles and `fixtures/compat-matrix/local-library-scenarios-2.0.json`.
- [x] Make official built-in mod-list handling discover the built-ins available beside the selected Factorio binary.

### v2.1.0 Spike / Defer Decisions

- [x] Pipeline extent multiplier is promoted from spike to implemented `v2.1.0` feature, gated by startup-setting compatibility proof.
- [x] Thruster fuel/oxidizer productivity is promoted from spike to implemented `v2.1.0` feature, gated by exact recipe-productivity proof.
- [x] Oil/fluid productivity is promoted from spike to implemented `v2.1.0` feature, gated by fluid-output recipe-productivity proof.
- [ ] Agricultural yield / fruit yield is spike-only unless a clean bounded path exists.
- [ ] Quality module enrichment is spike/defer or add-on; do not implement runtime module mutation in core MIR.
- [ ] Roboport range is spike/defer unless a clean native modifier or small prototype-tier path exists.
- [ ] True thruster thrust research remains rejected/deferred unless Factorio exposes a native modifier.
- [ ] Runtime platform speed mutation remains rejected.
- [ ] Runtime quality odds mutation remains rejected.
- [ ] Refrigeration, greenhouses, super-bacteria, and broad fluid systems remain companion/defer scope.

### v2.1.0 Acceptance Criteria

- [x] Every shipped feature has a clear implementation type: native modifier, recipe productivity, scripted event, prototype unlock, or startup setting.
- [x] No shipped feature uses broad `on_tick` scanning.
- [x] Any deferred `v2.0.5` scripted feature has its blocker closed or remains disabled/deferred.
- [x] Every scripted feature documents storage keys, recomputation events, disable behavior, reversal behavior, and multi-force behavior at the conservative default-off claim level.
- [x] Any new recipe-productivity stream proves exact recipe IDs and no vanilla/other-mod infinite duplicate.
- [x] Every startup prototype setting documents when it is applied and why it cannot be runtime research.
- [x] Compatibility tests include no Space Age, Space Age, Space Age without Quality where supported, custom science/lab fixtures, and targeted duplicate-productivity fixtures.
- [x] Removed preset/enable-policy behavior has validation for checkbox-only generated stream and base-extension decisions.
- [x] Targeted recipe-productivity competitor replacement has validation for full replacement and partial-coverage behavior.
- [ ] Broad native modifier skip/warn/prefer/allow policy remains deferred beyond diagnostic-only duplicate cargo/native modifier scenarios.
- [x] Icon resolver validation proves default base-only runs do not resolve generated icons to `__space-age__` paths, opt-in base-only runs can use installed Space Age icon paths, and Space Age runs still prefer intended Space Age art.
- [x] Package validation fails copied Space Age asset files unless an explicit source/license allowlist entry exists.
- [x] Conditional spikes are either promoted with proof or explicitly moved out of `v2.1.0`.
- [x] `info.json` version is bumped to `2.1.0`.
- [x] `changelog.txt` has a dated `2.1.0` entry.
- [x] Static validation enforces Factorio changelog syntax and the changelog-only 132-character line cap.
- [x] README, roadmap, compatibility docs, test results, and changelog are updated before release.
- [x] Runtime Factorio validation passes after the final compatibility refactor and Space Age productivity-stream split.
- [x] Compatibility audit smoke passes after the final package rebuild.
- [x] Do not publish the `2.1.0` archive until runtime validation, static validation, package build, diff check, and audit smoke all pass on the final tree.

## v2.1.5 Quick Feedback Patch

Use `v2.1.5` for small fixes after `v2.1.0`.

Through December 2026, keep the current-line release rhythm weekly when there is
a safe, validated Factorio `2.1` package to publish. Weekly releases may be
small bug fixes, compatibility profiles, docs corrections, validation/tooling
updates, or feature slices that pass the release gate. If a week has no safe
candidate, record the skip reason instead of publishing an under-tested archive.

Idea-mod audit planning lives in `docs/notes/mod-ideas-audit.md`.

| Audit lane | `v2.1.5` decision |
| --- | --- |
| Exact infinite recipe-productivity overlap | Ship only guarded known-competitor profiles. |
| Native lab-productivity duplicate | Ship the precise `Research_Productivity` skip. |
| Balance-heavy finite chains | Preserve/defer; do not silently replace. |
| Rule mutators, cap mutators, runtime productivity, and cost tools | Keep compatible/adjacent; do not absorb in this patch. |

- [ ] Fix bugs reported against `v2.1.0`.
- [x] Add small compatibility profiles only when the missing recipes/prototypes are concrete.
- [x] Add exact known-competitor profiles from the `ideamods_mix` audit.
- [x] Skip MIR lab productivity when infinite `research-productivity` or `laboratory-productivity-4` has the native lab-productivity effect.
- [x] Add a small effect fixture for `laboratory-productivity-4` before calling the skip effect-equivalent.
- [ ] Run the targeted external idea-mod load pass before tagging `v2.1.5`.
- [x] Add locale/docs/validation updates.
- [ ] Add proven recipe IDs to existing streams when no new architecture is needed.
- [ ] Rebalance costs or defaults for features already shipped in `v2.1.0`.

## v2.2.0 Larger Feature Wave

Use `v2.2.0` for the next larger batch after the `v2.1.x` feedback cycle. Most ideamods are compatibility signals, not planned MIR features. Keep this release to compatibility planner foundations plus the first new MIR-owned behavior proven by fixtures; do not turn it into every interesting idea-mod signal.

Idea-mod audit candidates should be promoted only after recipe-ID proof, balance decisions, licensing review, save-compatibility policy, and validation fixtures. Use `docs/compatibility-program.md` for the role taxonomy and one-archive audit template.

| Candidate | Source signal | First useful slice |
| --- | --- | --- |
| Compatibility planner/registry | All 50 idea-mod archives | Assign role enums, actions, non-actions, validation status, and public-claim boundaries before implementing broad features. |
| Cap-aware UX | Productivity cap and finite-limit helper mods | Diagnostics or explicit setting; never silent cap mutation. |
| Ore crushing productivity | Crushing Industry productivity research | Recipe-ID driven Crushing Industry stream or compatibility profile. |
| Tile/surface productivity | Asphalt, concrete, landfill, foundation productivity mods | Decide conservative defaults, exact cleanup rules, and optional high-value profile policy before implementation. |
| Overhaul material families | Pyanodon, Expanded Productivity Research, Crafting Efficiency | Pick one concrete family first; avoid a generic generator. |
| Native overlap policy | Lab, mining, solar, and other native productivity mods | General skip/warn/prefer/allow behavior with fixtures. |
| Companion boundary | Beacon/module/productivity-rule mutator mods | Decide whether this belongs outside MIR core. |

- [ ] Keep `docs/compatibility-program.md` and `docs/compatibility-matrix.md` current before making new compatibility claims.
- [ ] Add one structured audit row for each archive in `C:\Projects\Factorio\ideamods_mix` using the role enum and one-archive template.
- [ ] Add audited-zip checksum records for local compatibility campaigns so future Mod Portal updates do not silently change what was proved.
- [ ] Build the compatibility planner/registry before broad new stream work, with detected mods, actions, non-actions, warnings, and public-claim boundaries.
- [ ] Keep "replace exactly" separate from "cooperate/skip/prefer external" in code, docs, changelog, and release notes.
- [ ] Add save-compatibility notes before any feature removes, hides, or replaces external technologies that may already be researched.
- [ ] Build cap-aware diagnostics before adding balance-heavy productivity families.
- [ ] Treat ore-crushing productivity as the first clean new stream candidate only if recipe-ID fixtures pass.
- [ ] Require an explicit balance policy before shipping tile/surface productivity changes.
- [ ] Limit any overhaul material-family slice to one concrete family with fixture-proven recipe IDs.
- [ ] Keep Space Exploration, Krastorio 2, AAI, Bob's, and combination support as separate future matrices instead of one broad compatibility promise.
- [ ] Revisit pump/fluid/logistics work that was too large for `v2.1.0`.
- [ ] Revisit advanced settings UX if presets are not enough.
- [ ] Revisit bounded scripted research ideas after the framework has proven stable.
- [ ] Decide whether tile/surface productivity variants such as asphalt, concrete, landfill, and foundation need per-stream balance presets.
- [ ] Evaluate an ore-crushing productivity stream for Crushing Industry and overhaul mods.
- [ ] Evaluate broader Pyanodon/Bob/EV material-family streams only from concrete recipe families, not generic name overlap.
- [ ] Decide whether cap-aware finite conversion or warning UX belongs in MIR after reviewing productivity-cap helper mods.
- [ ] Decide whether module/beacon/productivity-rule mutation belongs in a companion mod rather than MIR core.
- [ ] Decide which growing ideas should split to companion mods.

## Legacy Backports

Do not reconstruct old releases commit-by-commit for `legacy`. A legacy release is a compatibility port of a tested current-line snapshot.

### v1.9.1 Backport From The Tested v2.1.0 Snapshot

- [x] Use the tested `v2.1.0` source point as the legacy snapshot.
- [x] Configure a real Factorio `2.0.x` binary for `release-targeted-2.0` and local-audit profiles.
- [x] Snapshot or merge that tested source point into the legacy backport branch.
- [x] Apply the same Factorio `2.0` compatibility patch rules as `v1.9.0`.
- [x] Build `dist/more-infinite-research_1.9.1.zip`.
- [x] Validate with a Factorio `2.0.x` binary.

### Planned v1.9.7 / v1.9.8 / v1.9.9 Factorio 2.0 Backports

- [ ] One week before Factorio `2.1` release, identify the latest tested MIR `2.x.x` source point.
- [ ] Backport that source point to Factorio `2.0` as `v1.9.7`.
- [ ] At Factorio `2.1` release, identify the latest tested MIR `2.x.x` source point.
- [ ] Backport that source point to Factorio `2.0` as `v1.9.8`.
- [ ] For the Factorio `2.1` stable/end-of-year support sweep, identify the latest tested MIR `2.x.x` source point.
- [ ] Backport that source point to Factorio `2.0` as final `v1.9.9`.
- [ ] Validate every `1.9.x` backport with a real Factorio `2.0.x` binary before publishing compatibility claims.

### v1.9.9 Final Factorio 2.0 Backport

- [ ] Treat the `v1.9.9` source point as the Factorio `2.1` stable/end-of-year support sweep snapshot.
- [ ] Backport that latest tested source snapshot to `legacy`.
- [ ] Set the legacy mod version to `1.9.9`.
- [ ] Treat `1.9.9` as the final planned Factorio `2.0` release.
- [ ] Verify the actual Factorio `2.1` stable status before making final-support claims.

### Older Factorio Line Backport Ladder

- [ ] Use `docs/notes/legacy-backport-cadence.md` as the source of truth for `1.8.x` and `1.7.x` target-line mapping.
- [ ] Treat the older-line campaign as tentative but maintainer-authorized planning, subject to validation and actual Factorio `2.1` release timing.
- [ ] During the Factorio `2.1` celebration window, attempt at most one older-line backport per day from the week before release through the week after release.
- [ ] Backport the week-before-Factorio-2.1-release snapshot to Factorio `1.1` as `v1.8.8`.
- [ ] Backport the Factorio `2.1` stable/end-of-year snapshot to Factorio `1.1` as `v1.8.9`.
- [ ] Backport the week-before-Factorio-2.1-release snapshot to Factorio `1.0` as `v1.8.6`.
- [ ] Backport the Factorio `2.1` stable/end-of-year snapshot to Factorio `1.0` as `v1.8.7`.
- [ ] Backport the week-before-Factorio-2.1-release snapshot to Factorio `0.17` as `v1.8.4`.
- [ ] Backport the Factorio-2.1-release snapshot to Factorio `0.17` as `v1.8.5`.
- [ ] Backport the week-before-Factorio-2.1-release snapshot to Factorio `0.16` as `v1.8.2`.
- [ ] Backport the Factorio-2.1-release snapshot to Factorio `0.16` as `v1.8.3`.
- [ ] Backport the week-before-Factorio-2.1-release snapshot to Factorio `0.15` as `v1.8.0`.
- [ ] Backport the Factorio-2.1-release snapshot to Factorio `0.15` as `v1.8.1`.
- [ ] After Factorio `2.1` release, backport the week-before-Factorio-2.1-release snapshot to Factorio `0.14` through `0.6` as `v1.7.8` through `v1.7.0`.
- [ ] Validate each older-line backport with a matching target Factorio binary when available, and document any missing validation in release notes.

<!-- MIR legacy RC plan start: tmp/0.15 -->
### `tmp/0.15` Factorio `0.15` RC Planning

This branch-specific section was added during the 2026-07-06 documentation-only RC planning sweep. It is tentative, maintainer-authorized planning for the experimental branch, not an implementation commit and not a release-candidate claim.

- [x] Add `docs/notes/rc-plan-factorio-0.15.md` for the target-line API/code/docs audit.
- [ ] Read docs/notes/rc-plan-factorio-0.15.md before any implementation change on tmp/0.15.
- [ ] Keep tmp/0.15 documentation-only until a target implementation pass is explicitly started.
- [ ] Use factorio-data tag 0.15.40 and the report source links as first compatibility contract.
- [ ] Close unsupported-surface blockers before creating an RC package.
- [ ] Validate with a real Factorio 0.15.x binary or document the missing binary before public archive.
- [ ] After 1.9.9, fold durable findings into permanent legacy and delete tmp/0.15 only when remote refs are no longer needed.
- [ ] Create a 0.15-specific science resolver and fixture.
- [ ] Confirm max_level/count_formula behavior in a 0.15.40 binary.
<!-- MIR legacy RC plan end: tmp/0.15 -->
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
- [x] `.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" -FailFast`
- [x] `.\scripts\Invoke-MIRExtendedTests.ps1 -Tier Static,Runtime,AuditSmoke -FactorioBin "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe" -FailFast -FailOnAuditFailures`
- [x] Manual-scenario, lockfile-resume, and profile-stub smoke paths for the compatibility audit tooling.
- [x] `.\scripts\Test-MIRBranchPolicy.ps1`
- [x] `git diff --check`
- [x] Load the release zip from a normal Factorio mods folder.
- [x] Record validation results in `docs/test-results.md`.
- [x] Commit docs, code, changelog, and package together for the tested candidate.
