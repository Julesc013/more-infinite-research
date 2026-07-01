# Architecture

More Infinite Research is organized around a compatibility-first data-stage pipeline.

## Data Stage Flow

`data.lua` loads only stable shared configuration and utility facades.

`data-updates.lua` is intentionally reserved for compatibility hooks that must run before final recipe and lab scanning.

`data-final-fixes.lua` runs the actual generation pipeline:

1. Generated stream technology creation.
2. Known competing recipe-productivity cleanup based on actual generated MIR effects.
3. Known competing base-extension cleanup when MIR's matching base extension is enabled.
4. Base technology infinite extensions.
5. Weapon speed overlap adjustment for generated continuations.
6. Max-level enforcement.
7. Optional diagnostics report flush.

This order gives the mod the best practical view of recipes, labs, science packs, and technologies created by other mods while still keeping this mod's final cleanup deterministic.

## Control Stage Boundary

The current source includes a small `control.lua` surface for scripted technologies such as spoilage preservation and agricultural growth speed. These runtime features remain default-off candidates because they are bounded and event-driven, but each claimed behavior must pass the named manual save validation before default enablement. Any behavior that fails proof moves to later current-line work.

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

Agricultural growth speed refreshes this force state on init, configuration changes, research finish, research reversal, and technology-effect resets. The current `v2.0.5` candidate only applies the multiplier at `on_tower_planted_seed`; it does not rescan existing plants.

## Utility Modules

`prototypes/util.lua` is a facade kept for compatibility with existing call sites. Domain logic lives in focused modules:

- `prototypes/lib/prototype-lookup.lua`: item-like prototype lookup, technology existence, ammo-category existence, Space Age detection.
- `prototypes/lib/science-packs.lua`: lab-input discovery, science-pack existence, end-game science-pack selection, lab-compatible ingredient validation, science-pack unlock prerequisites, ordered pack lists.
- `prototypes/lib/recipe-matching.lua`: item-output matching, item-pattern expansion, recipe category matching, hidden/recycling filtering.
- `prototypes/lib/technology-icons.lua`: borrowed icon copying, technology/item icon fallback, Wube-style constant overlays.
- `prototypes/lib/deepcopy.lua`: shared fallback for data-stage deep copies.
- `prototypes/lib/table-utils.lua`: deterministic table-key ordering helpers.
- `prototypes/lib/technology-cleanup.lua`: technology removal with prerequisite reference cleanup.

Keep new domain behavior in these modules rather than growing `util.lua`.

## Stream Configuration

`prototypes/config.lua` exposes:

- `M.shared`
- `M.streams`

The stream table is assembled by `prototypes/streams/init.lua` from:

- `prototypes/streams/productivity.lua`
- `prototypes/streams/direct-effects.lua`

Future expansion should add more stream domain modules rather than returning to one large config file.

Generated recipe-productivity streams can set `dynamic_items_from_lab_inputs = true` when their target item set should include every active lab input discovered during `data-final-fixes.lua`. The science-pack productivity stream uses this so custom science packs can receive productivity effects without hard-coded mod dependencies. If a future dynamic stream uses top-level `items` without `groups`, those items are copied into the generated group before lab inputs are appended.

## Compatibility Profiles

`prototypes/compat/profiles.lua` is the dedicated home for mod-specific stream patches.

Use profiles when a compatibility rule is tied to a known mod being active. Use general stream config only for behavior that should apply to every mod set.

Profile patches should use append fields such as `append_items`, `append_item_patterns`, `append_recipe_patterns`, `append_exclude_recipe_patterns`, `append_exclude_ingredient_patterns`, and `append_groups` when extending existing stream arrays. Direct field assignment remains available for intentional overrides.

Profiles are applied from `settings.lua` as well as the data stage, so profile entries must stay declarative. Do not inspect `data.raw` from profiles; prototype-dependent compatibility belongs in `data-updates.lua` or `data-final-fixes.lua`.

Weapon-speed overlap handling is intentionally narrower than general compatibility cleanup. MIR may remove rocket and cannon-shell speed effects from its own generated `weapon-shooting-speed` continuation when dedicated replacement speed techs are active, but it must not remove those effects from finite vanilla `weapon-shooting-speed-*` technologies. Those finite vanilla levels contain tank cannon fire-rate bonuses.

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

`mir-debug-recipe-matches` logs matched recipe names per generated productivity stream. When either diagnostics setting is enabled, duplicate recipe matches across streams are also reported as non-blocking warnings.

Native modifier overlap diagnostics are also non-blocking. They report that another infinite non-MIR technology already has the same native direct-effect identity, such as `cargo-landing-pad-count` or `max-cargo-bay-unloading-distance`, but they do not skip, merge, or mutate either technology in `v2.0.5`.

## Progression Settings

`ips-require-space-gate` and `mir-science-pack-ingredient-policy` deliberately control different parts of generated technologies.

- `ips-require-space-gate` adds the end-game science unlock as a prerequisite only. It does not change research ingredients.
- `mir-science-pack-ingredient-policy` changes research ingredients only. `configured` keeps each stream or extension's selected packs, `space` appends space science, `space-and-promethium` appends both high-end packs when available, `all-official` appends official base and Space Age packs without modded packs, and `all` appends every active lab science pack including compatible modded packs.

Both generated streams and base-technology extensions run through the same ingredient policy and end-game prerequisite helper so the settings apply consistently to all added infinite research.

## Validation

Use `scripts/Invoke-MIRValidation.ps1 -StaticOnly` for static checks.

Use `scripts/Invoke-MIRValidation.ps1 -FactorioBin C:\path\to\factorio.exe` for a runtime fixture load test.

Use `scripts/Build-MIRPackage.ps1` to rebuild the release archive when preparing an upload. Static validation builds an ignored validation archive from the current source tree and checks the archive root, metadata, load-critical entry files, locale files, migrations, and forbidden artifact paths.

Static package validation also recursively compares packaged files from the current source tree against the repository copy for the packaged source directories. Documentation and helper modules may be moved or nested inside their packaged trees without changing validation; the test follows the current tree instead of a fixed old layout. Text files are compared with normalized line endings so CI checkout settings do not create false failures; binary files are still compared by SHA-256.

Static validation also checks Factorio changelog formatting, including the required 99-dash section separators and an entry for the current `info.json` version.

Static validation checks every local fixture directory has `info.json`, a `mir-fixture-*` mod name, and at least one data-stage entry file.

Static validation rejects runtime tick handlers in `control.lua` and `control/**/*.lua`.

The fixture mods under `fixtures/` test custom science packs, custom labs, late recipe creation, the default `reduce` lab incompatibility behavior, the `skip` lab incompatibility behavior, science-pack ingredient policy modes, the end-game prerequisite gate, branch-gated cargo scenarios, finite vanilla-chain preservation, broad generation integrity, weapon-speed overlap safety, Omega-style drill productivity matching, and post-MIR assertions for runtime-sensitive generated technologies.

`mir-fixture-assert-generation-integrity` is the broad guardrail fixture. It runs after MIR in both base-only and Space Age runtime scenarios and verifies:

- generated `recipe-prod-*` stream technologies are infinite upgrades with effects and count formulas;
- every enabled vanilla numbered extension chain has exactly one infinite serial continuation after the highest finite level;
- disabled vanilla extension chains do not generate unless the validation harness explicitly force-enables them;
- every recipe has at most one infinite recipe-productivity owner;
- vanilla Space Age productivity technologies remain authoritative for LDS, plastic, processing units, and rocket fuel;
- circuit productivity ownership stays recipe-specific instead of relying on icon similarity.

Scripted technology validation must add existing-save load tests, research-finish/reversal tests, existing spoilable-stack tests, multi-force tests, and checks that the new effects remain event-driven rather than tick-scanned.

For API proof status and unresolved API questions, see `docs/api-proof-points.md`.

For named manual save scenarios, see `docs/manual-test-plan.md`.
