# Architecture

More Infinite Research is organized around a compatibility-first data-stage pipeline.

## Data Stage Flow

`data.lua` loads only stable shared configuration and utility facades.

`data-updates.lua` is intentionally reserved for compatibility hooks that must run before final recipe and lab scanning.

`data-final-fixes.lua` runs the actual generation pipeline:

1. Startup-only prototype passes such as the opt-in pipeline extent multiplier.
2. Known competing recipe-productivity preparation from active compatibility profiles.
3. Generated stream technology creation, with recipe-productivity ownership delegated to compatibility owner and adoption modules.
4. Known competing recipe-productivity cleanup based on actual generated MIR effects.
5. Known competing base-extension cleanup when MIR's matching base extension is enabled.
6. Base technology infinite extensions.
7. Weapon speed overlap adjustment for generated continuations.
8. Max-level enforcement.
9. Generated-technology effect safety validation.
10. Optional diagnostics and audit report flush.

This order gives the mod the best practical view of recipes, labs, science packs, and technologies created by other mods while still keeping this mod's final cleanup deterministic.

## Control Stage Boundary

The current `dev` branch includes a small `control.lua` surface for scripted technologies such as spoilage preservation and agricultural growth speed. These runtime features ship as disabled-by-default experimental candidates because they are bounded and event-driven. Stronger behavior claims, default enablement, or broad existing-save guarantees still require the named manual save validation.

The runtime layer is intentionally narrow:

- Prefer native technology modifiers and recipe productivity whenever the engine exposes them.
- Use scripted effects only when they can be event-driven.
- Avoid per-tick inventory, belt, lab, container, surface, or broad entity scanning.
- Keep runtime handlers grouped under a small scripted-tech manager such as `control/scripted-techs.lua`.
- Route init, configuration change, research finish, research reversal, and technology-effects reset through one recomputation path.
- Handle runtime setting changes if runtime settings are introduced.
- Require each scripted feature to document storage keys, disable behavior, multiple-force behavior, and interaction with other mods touching the same state.
- Label scripted/global/sandbox features clearly in settings and player-facing docs.
- Static validation fails if `control.lua` or `control/**/*.lua` registers `defines.events.on_tick` or `script.on_nth_tick` without a future explicit allowlist.

Do not use runtime code to fake fluid physics, platform speed, module effects, or machine behavior when the requested feature is really a prototype/entity unlock or companion-mod feature.

Current control files:

- `control.lua`: loads the scripted technology manager.
- `control/scripted-techs.lua`: registers init, configuration change, research finish/reversal, technology-effect reset, and agricultural tower planting handlers.
- `control/effects/spoilage-preservation.lua`: applies the global spoil-time multiplier from the highest completed MIR spoilage preservation level.
- `control/effects/agricultural-growth-speed.lua`: shortens remaining growth time for newly planted agricultural tower plants.

Current migrations:

- `migrations/more-infinite-research_2.0.5.json`: maps the removed generated character trash-slot technology ID into the combined inventory/trash technology ID.
- `migrations/more-infinite-research_2.1.0.json`: maps the retired generated stone-product productivity technology ID into the new landfill productivity technology ID.

### Scripted Runtime Storage

All runtime storage is namespaced below `storage.mir`.

`storage.mir.scripted_techs` is reserved for manager-level state. It is currently initialized so future manager metadata has a stable namespace, but it does not store behavior state yet.

`storage.mir.spoilage_preservation` stores:

- `baseline`: the spoil-time modifier after removing MIR's last applied multiplier where possible.
- `effective_level`: the highest completed spoilage preservation level across non-enemy/non-neutral forces.
- `applied_multiplier`: MIR's actual multiplier after the final spoil-time value is clamped to Factorio's global range.
- `last_applied_value`: the spoil-time modifier value MIR last wrote.

Spoilage preservation recomputes from the stored baseline on init, configuration changes, research finish, research reversal, and technology-effect resets. If no non-enemy/non-neutral force has completed levels, the recomputed target is the baseline. If the stream is disabled or the technology disappears, MIR restores the baseline only when the current game value still matches the last value MIR wrote; otherwise it treats the current value as externally owned and records it as the new baseline.

`storage.mir.agricultural_growth_speed.force_multipliers` stores one entry per non-enemy/non-neutral force:

- `level`: completed agricultural growth speed levels for that force.
- `multiplier`: the force's clamped growth multiplier.

Agricultural growth speed refreshes this force state on init, configuration changes, research finish, research reversal, and technology-effect resets. The current candidate only applies the multiplier at `on_tower_planted_seed`; it does not rescan existing plants.

## Utility Modules

`prototypes/util.lua` is a facade kept for compatibility with existing call sites. Domain logic lives in focused modules:

- `prototypes/lib/prototype-lookup.lua`: item-like and fluid prototype lookup, technology existence, ammo-category existence, Space Age detection.
- `prototypes/lib/science-packs.lua`: lab-input discovery, science-pack existence, end-game science-pack selection, lab-compatible ingredient validation, science-pack unlock prerequisites, ordered pack lists.
- `prototypes/lib/recipe-matching.lua`: item/fluid-output matching, output-pattern expansion, recipe category matching, hidden/recycling filtering.
- `prototypes/lib/technology-icons.lua`: borrowed icon copying, explicit `icon_candidates` resolution, legacy technology/item/fluid icon fallback, Wube-style constant overlays.
- `prototypes/lib/deepcopy.lua`: shared fallback for data-stage deep copies.
- `prototypes/lib/table-utils.lua`: deterministic table-key ordering helpers.
- `prototypes/lib/technology-cleanup.lua`: technology removal with prerequisite reference cleanup.
- `prototypes/compat/productivity-owners.lua`: shared recipe-productivity owner classification, recipe allow-productivity checks, and owner record formatting.
- `prototypes/compat/productivity-family-adoption.lua`: data-stage adoption of safe residual recipes into configured existing productivity families plus the adoption signature mod-data.
- `prototypes/compat/competing-productivity.lua`: profile-driven replacement of known fully covered competing infinite recipe-productivity technologies.
- `prototypes/technology-effect-safety.lua`: blocks unsafe native effect types from MIR-generated technologies.

Keep new domain behavior in these modules rather than growing `util.lua`.

## Icon Asset Boundary

Generated technologies may borrow icon layers from active prototypes and then add
MIR's own effect-type badge. The `dev` line supports explicit `icon_candidates`
for ordered technology/item/icon fallback, but keeps the package boundary strict:

- use official DLC technology or item art when the relevant DLC mod is loaded
  and the active prototype provides that icon;
- optionally use direct official DLC icon paths such as `__space-age__` or
  `__elevated-rails__` in base-only games only when the user enables
  `mir-use-installed-space-age-icons`;
- otherwise fall back to base-game technology or item art, MIR-owned local art,
  or another clearly redistributable asset when Space Age is not loaded;
- do not copy original Space Age PNGs or other DLC assets into MIR as base-only
  fallbacks;
- require any MIR-packaged local art to have an explicit source/license note and
  package-validation coverage.

This keeps the OEM-plus look when the relevant Wube content is present without
turning MIR into a redistributable Space Age art cache.

## Stream Configuration

`prototypes/config.lua` exposes:

- `M.shared`
- `M.streams`

The stream table is assembled by `prototypes/streams/init.lua` from:

- `prototypes/streams/productivity.lua`
- `prototypes/streams/direct-effects.lua`

Future expansion should add more stream domain modules rather than returning to one large config file.

Generated recipe-productivity streams can set `dynamic_items_from_lab_inputs = true` when their target item set should include every active lab input discovered during `data-final-fixes.lua`. The science-pack productivity stream uses this so custom science packs can receive productivity effects without hard-coded mod dependencies. If a future dynamic stream uses top-level `items` without `groups`, those items are copied into the generated group before lab inputs are appended.

Fluid-output productivity streams use the same recipe-productivity generator as item streams. They should be split by recipe ownership/process family, not by every output fluid name. Multi-output recipes such as oil processing belong to one owner stream; conversion families such as oil cracking, lubricant, sulfuric acid and acid neutralization, and thruster fuel/oxidizer can be separate streams when their recipes do not overlap.

Direct-effect stream and base-extension generation must pass through `prototypes/technology-effect-safety.lua`. MIR must not add `character-item-pickup-distance` or `character-loot-pickup-distance` effects to any generated technology; large pickup radii can vacuum belt items into the player inventory and cause severe lag.

`mir-pipeline-extent-multiplier` is deliberately not research. It is a startup-only prototype pass in `prototypes/pipeline-extent.lua` because `FluidBox.max_pipeline_extent` is resolved from prototypes during load. The dropdown values and parser live in `prototypes/pipeline-extent-settings.lua`. The pass is loaded only when the parsed startup setting is not `100%`; at the default `100%`, MIR reads the setting gate and does not load the pipeline module, scan `data.raw`, log pipeline work, or mutate fluid boxes.

## Compatibility Profiles

`prototypes/compat/profiles.lua` is the dedicated home for mod-specific stream patches.

Use profiles when a compatibility rule is tied to a known mod being active. Use general stream config only for behavior that should apply to every mod set.

Profile patches should use append fields such as `append_items`, `append_item_patterns`, `append_recipe_patterns`, `append_exclude_recipe_patterns`, `append_exclude_ingredient_patterns`, and `append_groups` when extending existing stream arrays. Direct field assignment remains available for intentional overrides.

Profiles can also declare `known_competing_productivity.tech_patterns` for mods whose infinite recipe-productivity technologies are safe to replace only when every effect is covered by enabled MIR streams. The profile declares the known competitor shape; the data-stage replacement module still proves coverage before it ignores or removes anything.

Profiles are applied from `settings.lua` as well as the data stage, so profile entries must stay declarative. Do not inspect `data.raw` from profiles; prototype-dependent compatibility belongs in `data-updates.lua` or `data-final-fixes.lua`.

Weapon-speed overlap handling is intentionally narrower than general compatibility cleanup. MIR may remove rocket and cannon-shell speed effects from its own generated `weapon-shooting-speed` continuation when dedicated replacement speed techs are active, but it must not remove those effects from finite vanilla `weapon-shooting-speed-*` technologies. Those finite vanilla levels contain tank cannon fire-rate bonuses.

## Compatibility Planner Direction

The next compatibility-heavy architecture step is a planner layer, not a broad
new generator. The durable policy is in `docs/compatibility-program.md`.

Keep the responsibilities separate:

- Stream definitions describe MIR-owned effects.
- Recipe resolvers decide which visible recipes a stream may own.
- Competitor profiles identify possible external owners but do not decide removal.
- Native modifier overlap policy decides skip, warn, prefer, coexist, or off behavior for non-recipe effects.
- Diagnostics explain generated actions and deliberate non-actions.
- Fixtures prove exact duplicates, wrong values, mixed effects, cap changes, native overlaps, and loaded rule mutators.

Compatibility adapters should register facts about known external mods. They
should not generate MIR content directly. Streams generate content; adapters
classify external owners and constraints; diagnostics explain the resulting plan.

The first planner slice in `v2.1.5` is diagnostics-only. It emits active
compatibility-role rows, a planner summary, and recipe-cap warnings when
diagnostics are enabled. It does not add streams, change recipe caps, change
maximum levels, or broaden cleanup beyond the guarded exact-overlap model.

`v2.2.0` adds the compiler spine behind that diagnostics surface. The compiler
builds typed facts for recipes, technologies, machines, labs, owners, and rule
surfaces; emits `DecisionRecord`-style rows for generated MIR technologies and
diagnostic-only blockers; reports obvious loop-risk flags; reports lab matrices;
and carries useful-level estimates for cap warnings. This path is report-only:
unknown or risky mod behavior is observed before any new automatic stream emits.

`v2.2.0` also starts the procedural compatibility kernel documented in
`docs/procedural-compatibility-kernel.md`. The first capability resolvers are
report-first:

- loader manufacturing classification from item `place_result`, placed loader
  entity type, and recipe output evidence;
- mining-drill manufacturing classification from item `place_result`, placed
  mining-drill entity type, and recipe output evidence;
- native modifier ownership observation for selected lab, mining, logistics, and
  robot effect types.

Those rows explain existing MIR behavior; they do not create a general
productivity generator. Existing streams still own emission. For example, loader
recipes are covered by belt productivity when visible, mining-drill recipes are
covered by mining drill productivity when visible, and native mining-yield
modifiers remain separate from drill manufacturing productivity.

The kernel now has enforceable platform pieces:

- schema versions in `prototypes/lib/mir/schema.lua`;
- resolver contract validation in `prototypes/lib/capabilities/contract.lua`;
- capability-specific policy in `prototypes/lib/policy/capabilities.lua`;
- generated stream manifest metadata in
  `prototypes/planner/generated-stream-manifest.json`;
- machine-readable claims in `fixtures/compat-matrix/claims.json`;
- static linting through `scripts/Test-MIRPolicyLints.ps1`;
- report drift comparison through `scripts/Compare-MIRPlannerReports.ps1`;
- negative capability fixtures for loop risks, hidden recipes, cap-zero recipes,
  and structural loader/drill decoys.

New mod support should add policy and fixtures first. New behavior classes
should add or extend a capability resolver. New false positives should become
classifier or policy fixes. New bug reports should become negative fixtures.

The `3.0.0` line promotes this kernel into the public compatibility compiler
architecture. Use `docs/notes/3.0.0-compatibility-compiler-charter.md` as the
source of truth for the 3.0 charter, invariants, module boundaries, non-goals,
release ladder, and acceptance gates. Use `docs/capabilities.md`,
`docs/policy-overlays.md`, `docs/decision-records.md`,
`docs/stream-manifest.md`, `docs/compatibility-claims.md`, `docs/testing.md`,
and `docs/maintainer-guide.md` for the focused 3.0 subsystem guidance.
Use `docs/notes/3.0.0-repository-structure.md` for the concrete 3.0 repository
shape: thin Factorio root files, the `prototypes/mir/` compiler namespace,
Factorio adapters under `platform/`, legacy shims for backporting, and the
development-only workspace boundary.

## Diagnostics

`mir-debug-generation-report` enables a structured log report. The report records generated and skipped streams/extensions with:

- key
- status
- reason
- science packs
- prerequisites
- effect count
- lab compatibility status
- icon source hint
- native direct-effect overlap rows, including effect type, target, and existing infinite non-MIR technology owners

Use this setting when triaging user reports. It is off by default to avoid noisy logs.

When `mir-debug-generation-report` is enabled, MIR also emits an `Audit report` block with stable `audit schema=1 kind=...` rows. These rows mirror stream, extension, native-overlap, recipe-owner, compatibility-role, compatibility-plan, recipe-cap, fact-registry, decision, rule-mutation, loop-risk, lab-matrix, and capability decisions in a parser-friendly key/value format for `scripts/Invoke-MIRCompatAudit.ps1` and future large-mod compatibility sweeps.

Recipe-cap diagnostics compare generated recipe-productivity effects with the
recipe's `maximum_productivity` value. Default caps stay quiet except for the
summary row. Lowered, raised, zero, unusual, or effectively uncapped values are
reported as diagnostics so players and compatibility audits can see when an
infinite stream may become misleading. `v2.2.0` also reports a useful-level
estimate for warning rows. MIR does not change recipe caps by default.

`mir-debug-recipe-matches` logs matched recipe names per generated productivity stream. When either diagnostics setting is enabled, duplicate recipe matches across streams are also reported as non-blocking warnings.

Native modifier overlap diagnostics are also non-blocking. They report that another infinite non-MIR technology already has the same native direct-effect identity, such as `cargo-landing-pad-count` or `max-cargo-bay-unloading-distance`, but they do not skip, merge, or mutate either technology unless a narrow effect-proven skip policy exists.

## Progression Settings

`ips-require-space-gate` and `mir-science-pack-ingredient-policy` deliberately control different parts of generated technologies.

- `ips-require-space-gate` adds the end-game science unlock as a prerequisite only. It does not change research ingredients.
- `mir-science-pack-ingredient-policy` changes research ingredients only. `configured` keeps each stream or extension's selected packs, `space` appends space science, `space-and-promethium` appends both high-end packs when available, `space-age-progression` adds Space Age gateway packs only when the selected packs already imply Space Age progression, `official-progression` fills missing official prerequisite-style packs implied by the selected official packs, `mod-progression` follows the loaded technology graph to infer missing lab-compatible packs for selected official or modded science packs, `all-official` appends official base and Space Age packs without modded packs, and `all` appends every active lab science pack including compatible modded packs.

Both generated streams and base-technology extensions run through the same ingredient policy and end-game prerequisite helper so the settings apply consistently to all added infinite research.

## Validation

Use `scripts/Invoke-MIRValidation.ps1 -StaticOnly` for static checks.

Use `scripts/Invoke-MIRValidation.ps1 -FactorioBin C:\path\to\factorio.exe` for a runtime fixture load test.

Use `scripts/Invoke-MIRCompatAudit.ps1` for mod-portal driven compatibility cataloging. It writes generated lock/report artifacts under an ignored output directory, uses `fixtures/compat-matrix/` for committed scenario intent, executes manual scenarios with `-RunManualScenarios`, generates local-library stress scenarios with `-RunGeneratedLocalScenarios`, resumes or shards prior locks with `-FromLockfile`, `-StartIndex`, `-Count`, and `-CandidateNames`, resolves supplied local root/library zips before Mod Portal metadata, supports `-Offline` for read-only local library sweeps, applies a per-scenario Factorio timeout, skips unresolved dependency scenarios before load testing unless `-ContinueOnDependencyFailure` is set, checkpoints load results after each scenario, and downloads third-party mods only when credentials are provided explicitly.

The compatibility runner writes isolated mod lists rather than inheriting the user's normal Factorio enabled-mod state. Official built-ins are listed explicitly and disabled unless the scenario needs them; requiring `space-age` expands to the full official bundle. Parsed audit rows are tolerant of blank log lines so checkpointed overnight results can still be converted after interrupted runs.

Use `scripts/Convert-MIRCompatAuditResults.ps1` after load-test runs to group failures into actionable buckets and emit `compat-failures.grouped.json`, `compat-summary.md`, `profile-candidates.json`, `compat-observations.*`, and `missing-dependencies.*`. The grouped output records total, expected, and unexpected failure counts. Compatibility observations record planner rows, recipe-cap warnings, compiler decisions, rule-surface rows, loop-risk rows, fact summaries, and lab matrices without turning them into failures. Expected failures mostly come from reviewed rules in `fixtures/compat-matrix/expected-failures.json`; successful-load audit observations that represent MIR's intentional conservative behavior, such as missing-prototype stream skips and unknown-external-owner suppression, are also kept non-blocking by default.

Use `scripts/New-MIRCompatProfileStub.ps1` only to generate review-required Lua stubs from grouped audit evidence. Generated stubs are not enabled profiles.

Use `scripts/Invoke-MIRExtendedTests.ps1` as the wrapper for repeatable tiers such as `Static`, `Runtime`, `AuditSmoke`, `Top25Base`, `Top25SpaceAge`, `ManualScenarios`, `LocalModZips`, `LocalLibraryScenarios`, `GeneratedLocalScenarios`, and opt-in sharded `Full10K*` runs. `scripts/Start-MIROvernightLocalSweep.ps1` is the safer human-facing entrypoint for the local Factorio `2.1` offline zip-library sweep; it validates paths, starts a transcript, runs the strict release gate, then delegates to the extended wrapper for the prioritized local tiers. Both wrappers now emit self-describing run artifacts: `run-manifest.json`, `events.jsonl`, `artifact-index.json`, and `index.html`. `scripts/Show-MIROvernightSummary.ps1` is the matching morning triage helper for grouped failures, missing dependencies, profile-candidate counts, and artifact paths. `AuditSmoke` uses the deterministic `space-age-baseline` manual-scenario metadata path so strict gates do not depend on volatile catalog ordering. `-CollectAll` is the exploratory/overnight mode. `-FailFast -FailOnAuditFailures` is the strict gate mode, where grouped unexpected audit failures make the wrapper fail. The self-hosted workflow calls this wrapper rather than duplicating audit logic in YAML.

Use `scripts/mir.ps1` as the stable developer-facing command facade. It keeps existing scripts as implementation details and adds memorable verbs for release gates, overnight local sweeps, local/top-25 audits, reports, package builds, profile stubs, run profiles, and local mod-library indexing. Shared operational helpers live under `scripts/MIRCli/`; treat them as a private helper folder, not as a framework that must be expanded before useful testing work can continue.

Use `scripts/Build-MIRPackage.ps1` to rebuild the release archive when preparing an upload. Static validation builds an ignored validation archive from the current source tree and checks the archive root, metadata, load-critical entry files, locale files, migrations, and forbidden artifact paths.

Static package validation also recursively compares packaged files from the current source tree against the repository copy for the packaged source directories. The release zip intentionally excludes developer-only docs, fixtures, scripts, and task ledgers; those remain repository evidence, not shipped mod payload. Text files are compared with normalized line endings so CI checkout settings do not create false failures; binary files are still compared by SHA-256.

Use `scripts/mir.ps1 release docs-only` or `scripts/mir.ps1 release docs-refresh` for documentation-only refreshes after a clean full release gate. The command runs the fast package/static validation path and rejects non-doc/package changes so prototype, script, fixture, locale, or runtime behavior changes still require the full gate.

Static validation also checks Factorio changelog formatting, including the required 99-dash section separators, the current `info.json` version, the changelog-only 132-character line cap, and blocked internal-process wording.

Static validation checks every loadable local fixture directory has `info.json`, a `mir-fixture-*` mod name, and at least one data-stage entry file. Non-mod audit inputs under `fixtures/compat-matrix/` and `fixtures/run-profiles/` are excluded from fixture-mod validation.

Static validation rejects runtime tick handlers in `control.lua` and `control/**/*.lua`.

Static validation also rejects unsafe pickup reach effect types outside the dedicated safety guard.

The fixture mods under `fixtures/` test item-based science packs, custom labs, late recipe creation, the default `reduce` lab incompatibility behavior, the `skip` lab incompatibility behavior, science-pack ingredient policy modes, the end-game prerequisite gate, base-only cargo skip behavior, Space Age cargo logistics effect shape, Maraxis-like duplicate cargo modifier diagnostics, finite vanilla-chain preservation, broad generation integrity, unsafe pickup reach exclusion, weapon-speed overlap safety, Omega-style drill productivity matching, fluid-output productivity ownership, pipeline extent startup scaling, and post-MIR assertions for runtime-sensitive generated technologies.

`mir-fixture-assert-generation-integrity` is the broad guardrail fixture. It runs after MIR in both base-only and Space Age runtime scenarios and verifies:

- generated `recipe-prod-*` stream technologies are infinite upgrades with effects and count formulas;
- every enabled vanilla numbered extension chain has exactly one infinite serial continuation after the highest finite level;
- disabled vanilla extension chains do not generate unless the validation harness explicitly force-enables them;
- every recipe has at most one infinite recipe-productivity owner;
- vanilla Space Age productivity technologies remain authoritative for LDS, plastic, processing units, and rocket fuel;
- circuit productivity ownership stays recipe-specific instead of relying on icon similarity.
- no technology in the fixture environment carries the blocked character item-pickup or loot-pickup reach effects.

Scripted technology validation must add existing-save load tests, research-finish/reversal tests, existing spoilable-stack tests, multi-force tests, and checks that the new effects remain event-driven rather than tick-scanned.

For API proof status and unresolved API questions, see `docs/api-proof-points.md`.

For named manual save scenarios, see `docs/notes/manual-test-plan.md`.
