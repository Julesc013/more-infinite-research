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
5. Vanilla weapon speed adjustment.
6. Max-level enforcement.
7. Optional diagnostics report flush.

This order gives the mod the best practical view of recipes, labs, science packs, and technologies created by other mods while still keeping this mod's final cleanup deterministic.

## Future Control Stage Boundary

The post-v2.0 feature plan allows a small `control.lua` surface for scripted technologies such as spoilage preservation and agricultural growth speed.

Keep that runtime layer narrow:

- Prefer native technology modifiers and recipe productivity whenever the engine exposes them.
- Use scripted effects only when they can be event-driven.
- Avoid per-tick inventory, belt, lab, container, surface, or broad entity scanning.
- Keep runtime handlers grouped under a small scripted-tech manager such as `control/scripted-techs.lua`.
- Route init, configuration change, research finish, research reversal, and technology-effects reset through one recomputation path.
- Require each scripted feature to document storage keys, disable behavior, multiple-force behavior, and interaction with other mods touching the same state.
- Label scripted/global/sandbox features clearly in settings and player-facing docs.

Do not use runtime code to fake fluid physics, platform speed, module effects, or machine behavior when the requested feature is really a prototype/entity unlock or companion-mod feature.

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

Use this setting when triaging user reports. It is off by default to avoid noisy logs.

`mir-debug-recipe-matches` logs matched recipe names per generated productivity stream. When either diagnostics setting is enabled, duplicate recipe matches across streams are also reported as non-blocking warnings.

## Progression Settings

`ips-require-space-gate` and `mir-science-pack-ingredient-policy` deliberately control different parts of generated technologies.

- `ips-require-space-gate` adds the end-game science unlock as a prerequisite only. It does not change research ingredients.
- `mir-science-pack-ingredient-policy` changes research ingredients only. `configured` keeps each stream or extension's selected packs, `space` appends space science, `space-and-promethium` appends both high-end packs when available, `all-official` appends official base and Space Age packs without modded packs, and `all` appends every active lab science pack including compatible modded packs.

Both generated streams and base-technology extensions run through the same ingredient policy and end-game prerequisite helper so the settings apply consistently to all added infinite research.

## Validation

Use `scripts/Invoke-MIRValidation.ps1 -StaticOnly` for static checks.

Use `scripts/Invoke-MIRValidation.ps1 -FactorioBin C:\path\to\factorio.exe` for a runtime fixture load test.

Use `scripts/Build-MIRPackage.ps1` to rebuild the release archive. Static validation checks the committed archive root, metadata, locale files, docs, and forbidden artifact paths.

Static package validation also compares key packaged source, documentation, and locale files against the repository copy so a stale zip with correct metadata is rejected.

Static validation also checks Factorio changelog formatting, including the required 99-dash section separators.

The fixture mods under `fixtures/` test item-based science packs, custom labs, late recipe creation, the default `reduce` lab incompatibility behavior, the `skip` lab incompatibility behavior, science-pack ingredient policy modes, the end-game prerequisite gate, base-only cargo skip behavior, Space Age cargo logistics effect shape, finite vanilla-chain preservation, and post-MIR assertions for runtime-sensitive generated technologies.

Future validation for scripted technologies should add existing-save load tests, research-finish/reversal tests, and checks that the new effects remain event-driven rather than tick-scanned.
